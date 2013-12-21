#!/usr/bin/env ruby

require 'peach'
require 'rest-client'
require 'thor'
require 'yaml'
require 'rebay'
require 'logger'
require 'pry'
require 'pry-debugger'
require 'nokogiri'

require_relative 'ruby-mws/base'
require_relative 'math-tools'
require_relative 'extentions'

class EbayMining < Thor

  def initialize(*args)
    super

    @settings = YAML.load File.read(File.dirname(__FILE__) +'/ebay-mining-tool.yml')
    @mapping = YAML.load(File.read(File.dirname(__FILE__) + '/mapping.yml'))

    init_rebay
  end

  desc 'Get products from ebay by category', 'Get products by category in decreasing order using the find products API and limited to a category'
  option :threads, default: 10,type: :numeric
  option :log, default: 'log-get-products-by-category.log'
  option :must_have_full_price, type: :boolean

  def mine_by_category(category_id, number_of_pages)


    logger = Logger.new options[:log]
    products = Array.new

    product_properties = YAML.load File.read(File.dirname(__FILE__) + '/product-properties.yml')

    ebay_mapping = @mapping[:ebay_details_mapping][category_id.to_sym]
    properties_extractors = Hash[ebay_mapping[:extractors].empty_if_nil.map { |k, v| [k, product_properties[k] + v] }]
    start = Time.new

    (1..number_of_pages.to_i).peach(options[:threads]) do |page|

      begin
        current_page = page

        response = @shopping.find_products(CategoryID: ebay_mapping[:category_id], MaxEntries: 20, PageNumber: current_page, IncludeSelector: 'Details')

        next if response.results.nil?

        results = response.results

        results.peach(options[:threads]) do |x|

          begin

            response = RestClient.get x['DetailsURL']

            response = response.force_encoding('utf-8')

            original_name = x['Title']

            product_id = x['ProductID']['Value']

            html = Nokogiri::HTML response

            product_properties = Hash[html.css('table')[5].css('tr').map { |x| x.css('td').select.map { |p| p.text } }.select { |x| x.length == 2 }]
            description = html.css('table')[5].css('tr')[1].text

            extracted_properties = Hash.new
            ebay_mapping[:properties].each do |prop|
              extracted = product_properties[prop]
              next if extracted.nil?

              extracted = extracted.split(', ') if extracted.include? ','
              extracted_properties[prop] = extracted if not extracted.nil?
            end

            name = extracted_properties
            .select { |x| ebay_mapping[:title].include? x }
            .map { |k, v| v }
            .join(' ')
            .split(' ')
            .inject([]) { |sum, x| sum << x if sum.last != x; sum }
            .join(' ')

            extracted_properties = Hash[extracted_properties.map { |k, v| [k.downcase.gsub(' ', '_'), v] }]

            logger.info "Working on #{name}"

            new_items_by_product = @finder
            .find_items_by_product({productId: product_id, :'itemFilter(0).name' => 'ListingType', :'itemFilter(0).value' => 'FixedPrice', :'itemFilter(1).name' => 'Condition', :'itemFilter(1).value(0)' => '1000'})
            .results.empty_if_nil

            used_items_by_product = @finder
            .find_items_by_product({productId: product_id, :'itemFilter(0).name' => 'ListingType', :'itemFilter(0).value' => 'FixedPrice', :'itemFilter(1).name' => 'Condition', :'itemFilter(1).value(0)' => '3000'})
            .results.empty_if_nil

            next if options[:must_have_full_price] && (new_items_by_product.empty? || used_items_by_product.empty?)

            product = {
                name: name,
                original_name: original_name,
                details_url: x['DetailsURL'],
                product_id: product_id,
                description: description,
                properties: extracted_properties,
                item_count: new_items_by_product.count + used_items_by_product.count
            }


            properties_extractors.map { |k, v|
              extracted = v.map { |x| original_name.scan /#{x}/i }.flatten.map(&:downcase)
              product[k]= extracted.first if extracted.any?
            }

            new_items = new_items_by_product.to_a
            .map { |x| x['sellingStatus']['currentPrice']['__value__'].to_f }

            used_items = used_items_by_product.to_a
            .map { |x| x['sellingStatus']['currentPrice']['__value__'].to_f }

            new_price = MathTools.analyze(new_items.remove_growth_over(1.5))
            used_price = MathTools.analyze(used_items.remove_growth_over(1.5))

            price = Hash.new

            price[:new] = new_price[:median] if not new_price.nil?
            price[:used] = used_price[:median] if not used_price.nil?

            product[:price] = price if not price.empty?


            products << product

          rescue Exception => ex
            logger.error "Product name: #{name}\n Product id: #{product_id}\n #{ex.message}\n#{ex.backtrace.join("\n ")}"
          end

        end

      rescue Exception => ex
        logger.error "#{ex.message}\n#{ex.backtrace.join("\n ")}"
      end

    end

    logger.info "Took: #{(Time.now-start)/60} min"
    number_of_products = products.length

    logger.info "Number of products found is: #{number_of_products}"
    file_name = get_default_file_name_for_category(category_id)
    logger.info "Saved to file #{file_name}"

    File.open(file_name, 'w') { |f| f.write JSON.pretty_generate(products) }
  end

  desc 'Stream the properties to STDOUT', 'Takes the category id and a list of properties'
  option :reduce, default: false

  def stream_properties(category_id, *fields)
    products = JSON.parse File.read(get_default_file_name_for_category(category_id)), symbolize_names: true

    products.each { |x|
      fields.each { |field|
        if field.include?(' ')
          $stdout.puts field.split(' ').map { |part| part.split('.').map(&:to_sym).inject(x) { |sum, x| sum[x] } }.join(' ')
        elsif field.include?('.')
          $stdout.puts field.split('.').map(&:to_sym).inject(x) { |sum, x| sum[x] }
        else
          $stdout.puts x[field.to_sym]
        end

      }
    }

  end

  desc 'extract-properties', 'Extract the properties into a json file'

  def extract_properties(category_id)
    products = JSON.parse File.read(get_default_file_name_for_category(category_id)), symbolize_names: true

    properties = Hash[
        products.map { |x|
          x[:properties].map { |k, v| [k, v] }
        }
        .flatten(1)
        .uniq
        .group_by { |x| x[0] }
        .map { |k, v| [k, v.map { |x| x[1] }.flatten.uniq.sort] }]

    File.write(get_default_file_name_for_category(category_id, 'properties'), JSON.pretty_generate(properties))

  end

  desc 'mine-and-extract', 'Mine and extract the details so it makes it ready for amazon'

  def mine_and_extract(categories, number_of_pages)
    if categories.include?(',')
      categories = categories.split(',')
    else
      categories = [categories]
    end

    categories.each { |x|
      invoke 'mine_by_category', [x, number_of_pages]
      invoke 'extract_properties', [x]
    }

  end

  desc 'product-items', 'detauls about a product using the finding API'
  option :condition, type: :string, default: ''

  def product_items(product_id)
    request = {productId: product_id, :'itemFilter(0).name' => 'ListingType', :'itemFilter(0).value' => 'FixedPrice'}

    if options[:condition].length > 0
      request[:'itemFilter(1).name'] = 'Condition'
      request[:'itemFilter(1).value'] = options[:condition]
    end

    items_by_product = @finder
    .find_items_by_product(request)
    .results

    $stdout.puts JSON.pretty_generate(items_by_product)
  end

  desc 'generate-matches', 'Generated a match file to use with Amazon'

  def generate_matches(file, category_id)
    products = file.parse_path_to_json
    ebay_mapping = @mapping[:ebay_details_mapping][category_id.to_sym]

    match_products = products
    .select { |x| x[:properties][:upc] }
    .map { |x|
      [x[:properties][:upc]]
      .flatten
      .map { |p|
        {
            query: p,
            matchers: ebay_mapping[:matchers].map { |m| x[:properties][m] }.compact,
            name: x[:original_name]
        }
      }
    }.flatten

    $stdout.puts match_products.to_json

  end

  private

  def init_rebay
    Rebay::Api.configure do |rebay|
      rebay.app_id = @settings[:ebay_app_id]
    end

    @shopping = Rebay::Shopping.new
    @finder = Rebay::Finding.new
  end

  def get_default_file_name_for_category(category_id, extra=nil)
    what_to_add = category_id
    what_to_add = "#{what_to_add}-#{extra}" if not extra.nil?

    "ebay-#{what_to_add}.json"
  end

end

EbayMining.start