#!/usr/bin/env ruby

require 'peach'
require 'rest-client'
require 'thor'
require 'yaml'
require 'rebay'
require 'logger'
require 'pry'
require 'pry-debugger'

require_relative 'ruby-mws/base'
require_relative 'math-tools'
class EbayMining < Thor

  def initialize(*args)
    super

    @settings = YAML.load File.read(File.dirname(__FILE__) +'/ebay-mining-tool.yml')
    @mapping = YAML.load(File.read(File.dirname(__FILE__) + '/mapping.yml'))

    init_rebay
  end

  desc 'Get products from ebay by category', 'Get products by category in decreasing order using the find products API and limited to a category'
  option :threads, default: 5
  option :log, default: 'log-get-products-by-category.log'

  def mine_by_category(category_id, number_of_pages)

    logger = Logger.new options[:log]
    products = Array.new

    start = Time.new

    (1..number_of_pages.to_i).peach(options[:threads]) do |page|

      begin
        current_page = page

        response = @shopping.find_products(CategoryID: category_id, MaxEntries: 20, PageNumber: current_page, IncludeSelector: 'Details')

        next if response.results.nil?

        results = response.results

        results.peach(options[:threads]) do |x|

          begin

            response = RestClient.get x['DetailsURL']

            response = response.force_encoding('utf-8')

            product_id = x['ProductID']['Value']

            properties = @mapping[:ebay_details_mapping][category_id.to_sym]

            extracted_properties = Hash.new
            properties[:properties].each do |prop|
              extracted = (response.scan(/>#{prop}.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil)
              next if extracted.nil?

              extracted = extracted.split(', ') if extracted.include? ','
              extracted_properties[prop] = extracted if not extracted.nil?
            end

            name = extracted_properties
            .select { |x|
              if not properties[:exclude_from_name].nil?
                !properties[:exclude_from_name].include?(x)
              else
                true
              end
            }
            .map { |k, v| v }
            .uniq.join(' ')
            .split(' ')
            .uniq
            .join(' ')

            extracted_properties = Hash[extracted_properties.map { |k, v| [k.downcase.gsub(' ', '_'), v] }]

            logger.info "Working on #{name}"

            items_by_product = @finder.find_items_by_product({productId: product_id, :'itemFilter.name' => 'ListingType', :'itemFilter.value' => 'AuctionWithBIN'}).results

            ebay = nil
            if not items_by_product.nil?

              next if items_by_product.first.kind_of?(Array)

              groups = items_by_product.group_by { |x|
                x['condition']['conditionId'].to_i
              }

              new_items = groups
              .select { |k| k < 2000 }
              .map { |k, v| v }
              .flatten
              .map { |x| x['listingInfo']['buyItNowPrice']['__value__'].to_i if x.kind_of?(Hash) && x.has_key?('listingInfo') && x['listingInfo'].has_key?('buyItNowPrice') }
              .select { |x| !x.nil? }

              used_items = groups
              .select { |k| k == 3000 }
              .map { |k, v| v }
              .flatten
              .map { |x| x['listingInfo']['buyItNowPrice']['__value__'].to_i if x.kind_of?(Hash) && x.has_key?('listingInfo') && x['listingInfo'].has_key?('buyItNowPrice') }
              .select { |x| !x.nil? }

              ebay = {
                  new: MathTools.analyze(new_items),
                  used: MathTools.analyze(used_items)
              }

            end

            ebay_new_range = (MathTools.percent_range(ebay[:new][:median], 0.1) rescue nil)
            ebay_used_range = (MathTools.percent_range(ebay[:used][:median], 0.1) rescue nil)

            products << {
                name: name,
                details_url: x['DetailsURL'],
                product_id: product_id,
                properties: extracted_properties,
                item_count: (items_by_product.length rescue nil),
                ebay_new_range: ebay_new_range,
                ebay_used_range: ebay_used_range,
                ebay: ebay,
            }

          rescue Exception => ex
            logger.error "Product name: #{name}\n #{ex.message}\n#{ex.backtrace.join("\n ")}"
          end

        end

      rescue Exception => ex
        logger.error "#{ex.message}\n#{ex.backtrace.join("\n ")}"
      end

    end

    logger.info "Took: #{(Time.now-start)/60} min"
    number_of_products = products.length

    logger.info "Number of products found is: #{number_of_products}"
    File.open(get_default_file_name_for_category(category_id), 'w') { |f| f.write JSON.pretty_generate(products) }
  end

  desc 'Stream the properties to STDOUT', 'Takes the category id and a list of properties'

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

  desc 'Extract properties for a category', 'Extract the properties into a json file'

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