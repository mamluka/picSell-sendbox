#!/usr/bin/env ruby

require 'peach'
require 'rest-client'
require 'thor'
require 'yaml'
require 'logger'
require 'nokogiri'
require 'pry'
require 'amazon/ecs'

require_relative 'math-tools'
require_relative 'extentions'
require_relative 'ruby-mws'

class AmazonMining < Thor

  def initialize(*args)
    super

    @mws = MWS.new(:aws_access_key_id => "AKIAIDZUEZILKOGLJNJQ",
                   :secret_access_key => "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",
                   :seller_id => "A25ONFDA24CSQ8",
                   :marketplace_id => "ATVPDKIKX0DER")

    @map = Amazon::Ecs.options = {
        :associate_tag => '1361-2493-1075',
        :AWS_access_key_id => 'AKIAJ3RA7HE7YCVMGRGQ',
        :AWS_secret_key => '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'
    }

    @amazon_etl = YAML.load(File.read(File.dirname(__FILE__) + '/amazon-etl.yml'))

    @debug_logger = Logger.new('log-amazon-mining-debug.log')
    @logger = Logger.new 'log-amazon-mine-by-query.log'
  end

  desc 'mine', 'Query data via stdin'

  option :use_asins, default: false
  option :allow_no_categories, default: false
  option :allow_any_sales_ranking, default: false

  def mine(category_id)

    category_id = category_id.to_sym

    product_properties = YAML.load File.read(File.dirname(__FILE__) + '/product-properties.yml')
    products = Array.new

    start = Time.now

    properties_extractors = Hash[@amazon_etl[category_id][:extractors].empty_if_nil.map { |k, v| [k, product_properties[k] + v] }]

    @logger.info 'Start new mining'
    queries = $stdin.readlines.map { |x| x.delete("\n") }.uniq

    queries_in_parallel = options[:use_asins] ? 10 : 3
    products_in_parallel = options[:use_asins] ? 1 : 5

    queries.uniq.peach(queries_in_parallel) do |query|

      begin

        (@logger.info 'Skipped because product query was empty'; next) if query.strip.length == 0

        @logger.info "Looking for #{query}"

        if options[:use_asins]
          products_asins = [query]
        else
          products_asins = search_by_query(query, {takes: 5, search_alias: @amazon_etl[category_id][:search][:search_alias]})
          (@logger.info 'Skipped because no asins were found in the search results'; next) if products_asins.empty?
        end

        amazon_request = {marketplace_id: 'ATVPDKIKX0DER', IdType: 'ASIN'}

        products_asins.each_with_index { |x, i| amazon_request["IdList.Id.#{i+1}"]=x }

        amazon_products = [@mws.products.get_matching_product_for_id(amazon_request)].flatten

        @logger.info "Found #{amazon_products.length} products for #{products_asins.length} asins at #{query} search"

        (@logger.info 'Skipped because amazon api returned no products'; next) if amazon_products.length == 0

        amazon_products.peach(products_in_parallel) { |x|

          begin

            amazon_product = x.product

            (@logger.info "Skipped because product was nil"; next) if amazon_product.nil?

            asin = amazon_product.identifiers.marketplace_asin.asin

            (@logger.info 'Skipped because product asin was already gathered'; next) if products.any? { |x| x[:asin] == asin }

            amazon_name = amazon_product.attribute_sets.item_attributes.title

            raw_properties = amazon_product.attribute_sets.item_attributes.to_hash

            properties = Hash.new
            if raw_properties['item_dimensions']
              properties[:weight] = raw_properties['item_dimensions']['weight']['_content_'] if raw_properties['item_dimensions']['weight']
              properties[:width] = raw_properties['item_dimensions']['width']['_content_'] if raw_properties['item_dimensions']['width']
              properties[:height] = raw_properties['item_dimensions']['height']['_content_'] if raw_properties['item_dimensions']['height']
              properties[:depth] = raw_properties['item_dimensions']['length']['_content_'] if raw_properties['item_dimensions']['length']
            end

            properties[:part_number] = raw_properties['part_number'] if raw_properties['part_number']
            properties[:color] = raw_properties['color'] if raw_properties['color']

            name_hash = augment_name(amazon_name, category_id, properties_extractors)

            amazon_name = name_hash[:amazon_name]
            original_name = name_hash[:original_name]

            brand = amazon_product.attribute_sets.item_attributes.brand
            model = amazon_product.attribute_sets.item_attributes.model || amazon_product.attribute_sets.item_attributes.partNumber

            (@logger.info "Skipped #{asin} because no sales ranking"; next) if amazon_product.sales_rankings.nil?

            if amazon_product.sales_rankings.sales_rank.kind_of?(Array)
              sales_rank = amazon_product.sales_rankings.sales_rank.min_by { |x| x.rank.to_i }.rank.to_i
            else
              sales_rank = amazon_product.sales_rankings.sales_rank.rank.to_i
            end

            amazon_url = "http://www.amazon.com/product-name/dp/#{asin}"

            (@logger.info "Skipped #{asin} because No brand and no model and no sales rank"; next) if brand.nil? || model.nil? || sales_rank.nil?
            (@logger.info "Skipped #{asin} because sale rank was above 150000"; next) if sales_rank > 150000 && !options[:allow_any_sales_ranking]

            categories = (Nokogiri::HTML(RestClient.get amazon_url).at('h2:contains("Look for Similar Items by Category")').parent.css('ul li').map { |x| x.css('a').map { |a| a.text }.join('::') } rescue nil)

            allow_no_categories = @amazon_etl[category_id][:allow_no_category]

            (@logger.info "Skipped #{asin} because found no categories and allow no categories is #{allow_no_categories}"; next) if (categories.nil? || categories.length == 0) && (!allow_no_categories & !options[:allow_no_categories])

            high_price = @mws.products.get_competitive_pricing_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin
            low_price_new = @mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'New'
            low_price_used = @mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'Used'


            competitive_pricing_analyze = MathTools.analyze(high_price.listing_price.empty_if_nil.map { |x| x[:price].to_i }.remove_growth_over(1.5))
            lowest_offer_new_analyze = MathTools.analyze(low_price_new.listing_price.empty_if_nil.map { |x| x[:price].to_i }.remove_growth_over(1.5))
            lowest_offer_used_analyze = MathTools.analyze(low_price_used.listing_price.empty_if_nil.map { |x| x[:price].to_i }.remove_growth_over(1.5))

            (@logger.info "Skipped #{asin} because no price info"; next) if competitive_pricing_analyze.nil? && lowest_offer_new_analyze.nil? && lowest_offer_used_analyze.nil?

            @logger.info amazon_name

            item_count = [competitive_pricing_analyze, lowest_offer_new_analyze, lowest_offer_used_analyze].compact.inject(0) { |sum, x| sum + x[:count] }

            price = Hash.new
            new_price = competitive_pricing_analyze || lowest_offer_new_analyze

            price[:new] = new_price.nil? ? nil : new_price[:median]
            price[:used] = lowest_offer_used_analyze[:median] if not lowest_offer_used_analyze.nil?

            min_price = @amazon_etl[category_id][:min_price]

            (@logger.info "Skipped #{asin} because price was below #{min_price}"; next) if !min_price.nil? && [price[:new], price[:used]].compact.min < min_price

            product = {
                id: asin,
                name: amazon_name,
                original_name: original_name,
                amazon_url: amazon_url,
                asin: asin,
                properties: properties,
                raw_properties: raw_properties,
                sales_rank: sales_rank,
                item_count: item_count,
                categories: categories,
                price: price,
                competitive_pricing: competitive_pricing_analyze,
                lowest_offer_new: lowest_offer_new_analyze,
                lowest_offer_used: lowest_offer_used_analyze,
            }


            properties_extractors.map { |k, v|
              extracted = v.map { |x| original_name.scan /#{x}/i }.flatten.map(&:downcase)
              product[k]= extracted.first if extracted.any?
            }

            products << product

          rescue Exception => ex
            @logger.error "Product name: #{amazon_name}\n Amazon name: #{amazon_name}\n #{ex.message}\n#{ex.backtrace.join("\n ")}"
          end
        }

      rescue Exception => ex
        @logger.error "Query: #{query}\n #{ex.message}\n#{ex.backtrace.join("\n ")}"
      end
    end


    products = products.uniq { |x| x[:asin] }

    @logger.info "Took: #{(Time.now-start)/60} min"
    number_of_products = products.length

    @logger.info "Number of products found is: #{number_of_products}"
    File.open(amazon_filename_by_category(category_id), 'w') { |f| f.write JSON.pretty_generate(products) }

  end

  desc 'match', 'Match products given query amd features to match'
  option :asins, type: :boolean
  option :threads, type: :numeric, default: 10

  def match(file, category_id)
    products = JSON.parse File.read(file), symbolize_names: true

    matched_products = products.pmap(options[:threads]) { |product|
      amazon_products = search_by_query product[:query], {return_value: :titles_and_asins, search_alias: @amazon_etl[category_id.to_sym][:search][:search_alias]}

      max_mismatch = product[:max_mismatch] || 0
      min_matches = product[:min_matches] || 1
      matched_product = amazon_products.select { |x|
        matches = product[:matchers].count { |p| x[:title] =~ /#{p}/i }
        matches >= product[:matchers].length-max_mismatch && matches >=min_matches
      }.first

      next product.merge matched: false, amazon_options: amazon_products if matched_product.nil?

      product.merge(matched_product).merge matched: true
    }
    output = JSON.pretty_generate matched_products

    output = matched_products.select { |x| x[:matched] }.map { |x| x[:asin] }.join("\n") if options[:asins]

    $stdout.puts output
  end

  desc 'extract-asins', 'Extract asins from json files'

  def extract_asins(file)
    items = file.parse_path_to_json
    items.map { |x| x[:asin] }.compact.each { |x| $stdout.puts x }
  end

  desc 'append-categories', 'Append categories to an existing feed on product in a json  output by match'

  def append_categories(file)
    products = file.parse_path_to_json

    products.each { |x|
      @logger.info "Now looking for categories for: #{x[:asin]}"

      categories = @mws.products.get_product_categories_for_asin(:marketplace_id => 'ATVPDKIKX0DER', :asin => x[:asin]).categories
      next if not categories

      x[:categories] = categories.map(&:to_hash)

      sleep 5
    }

    $stdout.puts products.to_json
  end

  desc 'top-100', 'No need for searching the text'

  def top_100(amazon_department_and_categories)

    if amazon_department_and_categories.include?(',')
      amazon_department_and_categories = amazon_department_and_categories.split(',')
    else
      amazon_department_and_categories = [amazon_department_and_categories]
    end

    fetch_urls = amazon_department_and_categories.map { |category| (1..5).map { |x|
      "http://www.amazon.com/x/zgbs/#{category}?_encoding=UTF8&pg=#{x}" }
    .concat((1..5).map { |x| "http://www.amazon.com/gp/most-gifted/#{category}?_encoding=UTF8&pg=#{x}" })
    .concat((1..5).map { |x| "http://www.amazon.com/gp/most-wished-for/#{category}?_encoding=UTF8&pg=#{x}" })
    .concat((1..5).map { |x| "http://www.amazon.com/gp/top-rated/#{category}?_encoding=UTF8&pg=#{x}" })
    .concat((1..5).map { |x| "http://www.amazon.com/gp/new-releases/#{category}?_encoding=UTF8&pg=#{x}" })
    }.flatten

    web_content = []

    fetch_urls.peach(fetch_urls.length) { |x|
      web_content << RestClient.get(x)
    }

    all_text = web_content.inject { |sum, x| sum + x }

    html = Nokogiri::HTML all_text

    asins = html.css('.zg_itemImmersion .zg_title a').map { |x| x.attributes['href'].value.strip.scan(/\/dp\/(.+?)$/)[0][0] }.uniq

    asins.each { |x|
      $stdout.puts x
    }

  end

  desc 'asins-by-query', 'Output asins using search and query in stdin'
  option :threads, default: 10
  option :asins_per_query, default: 10

  def asins_by_query(category_id)
    category_id = category_id.to_sym

    $stdin
    .readlines
    .map { |x| x.strip }
    .pmap(options[:threads]) { |x|
      search_by_query x, {takes: options[:asins_per_query], search_alias: @amazon_etl[category_id][:search][:search_alias]}
    }
    .flatten
    .select { |x| x.length > 0 }
    .each { |x|
      $stdout.puts x
    }
  end

  desc 'stream', 'Takes the category id and a list of properties'

  def stream_properties(category_id, *fields)
    products = JSON.parse File.read(amazon_filename_by_category(category_id)), symbolize_names: true

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

  desc 'test-name-augment', 'use category_id and name'

  def test_name_augmentation(name, category_id)
    category_id = category_id.to_sym

    category_properties = JSON.parse File.read(ebay_filename_by_category(category_id, 'properties')), symbolize_names: true

    properties_extractors = Hash[@amazon_etl[category_id][:extractors].empty_if_nil.map { |k, v| [k, category_properties[k] + v] }]

    $stdout.puts augment_name(name, category_id, properties_extractors)
  end

  desc 'get-products', 'Get a single product api response from amazon advertising API'

  def get_products

    asins = $stdin.readlines.map(&:strip)

    products =asins.map { |x|
      sleep 1
      @debug_logger.debug "Currently looking for: #{x}"

      response = Amazon::Ecs.item_lookup(x, {ResponseGroup: :ItemAttributes})
      (@debug_logger.debug "Skipped #{x} because no products in US"; next x) if response.items.empty?

      response.items.first.get_hash('ItemAttributes')
    }
    .map { |x|
      next x if !x.kind_of?(String)

      sleep 1
      @debug_logger.debug "Currently looking for: #{x} in UK"

      response = Amazon::Ecs.item_lookup(x, {ResponseGroup: :ItemAttributes, country: :uk})
      (@debug_logger.debug "Skipped #{x} because no products in UK"; next x) if response.items.empty?

      response.items.first.get_hash('ItemAttributes')
    }.map { |x|
      next x if !x.kind_of?(String)

      sleep 1
      @debug_logger.debug "Currently looking for: #{x} in CA"

      response = Amazon::Ecs.item_lookup(x, {ResponseGroup: :ItemAttributes, country: :ca})
      (@debug_logger.debug "Skipped #{x} because no products in CA"; next x) if response.items.empty?

      response.items.first.get_hash('ItemAttributes')
    }

    $stdout.puts JSON.pretty_generate(products)

  end

  private

  def amazon_filename_by_category(category_id, extra=nil)
    what_to_add = category_id
    what_to_add = "#{what_to_add}-#{extra}" if not extra.nil?

    "amazon-#{what_to_add}.json"
  end

  def ebay_filename_by_category(category_id, extra=nil)
    what_to_add = category_id
    what_to_add = "#{what_to_add}-#{extra}" if not extra.nil?

    "ebay-#{what_to_add}.json"
  end

  def augment_name(amazon_name, category_id, properties_extractors)

    original_name = amazon_name

    properties_extractors.each { |k, v| amazon_name = v.inject(amazon_name) { |name, x| name.split(' ').delete_if { |w| w.downcase == x.downcase }.join(' ') } }

    amazon_name = @amazon_etl[category_id][:bad_patterns].empty_if_nil.inject(amazon_name) { |name, x| name.gsub /#{x}/i, '' }
    amazon_name = @amazon_etl[category_id][:bad_phrases].empty_if_nil.inject(amazon_name) { |name, x| name.gsub /#{x}/i, '' }
    amazon_name = @amazon_etl[category_id][:bad_words].empty_if_nil.inject(amazon_name) { |name, x| name.split(' ').delete_if { |w| w.downcase == x.downcase }.join(' ') }

    if @amazon_etl[category_id].has_key? :replace_groups

      addition_to_name = @amazon_etl[category_id][:replace_groups][:patterns].map { |x|
        match = original_name.scan(/#{x[:pattern]}/i)

        {
            match: match.any? ? match[0][x[:group]] : '',
            key: x[:key]
        }
      }.inject(@amazon_etl[category_id][:replace_groups][:title]) { |sum, x|
        if !amazon_name.include? x[:match]
          sum.gsub x[:key], x[:match]
        else
          sum.gsub x[:key], ''
        end
      }.strip


    end

    {
        amazon_name: "#{amazon_name} #{addition_to_name}",
        original_name: original_name
    }
  end

  def search_by_query(query, options = {})
    begin
      takes = options[:takes] || 10
      search_alias = options[:search_alias] || :aps

      return_value = options[:return_value] || :asins

      search_url = URI::encode "http://www.amazon.com/s/search-alias=#{search_alias}&field-keywords=#{query.gsub '&', ' '}"

      @logger.debug search_url

      web_text = RestClient.get search_url

      web_text = web_text.force_encoding("ISO-8859-1").encode("UTF-8")

      File.open(File.dirname(__FILE__) + "/searches-html/#{query}.html", 'w') { |f| f.write web_text }
      @logger.info "Skipped because no product were matched by the query #{query}" if web_text.include? 'did not match any products'

      html = Nokogiri::HTML web_text

      query_response = []
      query_response = html.css('.productTitle')
      .map { |x| x.attributes['id'].value.split('_')[1] }
      .take(takes) if return_value == :asins

      query_response = html.css('.productTitle')
      .map { |x| {asin: x.attributes['id'].value.split('_')[1], title: x.css('a').text} } if return_value == :titles_and_asins

      query_response

    rescue Exception => ex
      @logger.error "#{ex.message}\n#{ex.backtrace.join("\n")}"
      ''
    end
  end

end

AmazonMining.start