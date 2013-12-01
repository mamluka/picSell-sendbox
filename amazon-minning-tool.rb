#!/usr/bin/env ruby

require 'peach'
require 'rest-client'
require 'thor'
require 'yaml'
require 'logger'
require 'nokogiri'
require 'pry'

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

    @amazon_etl = YAML.load(File.read(File.dirname(__FILE__) + '/amazon-etl.yml'))

    @debug_logger = Logger.new('log-amazon-mining-debug.log')
  end

  desc 'Read stdin and query the data in amazon', 'Query data via stdin'

  option :use_asins, default: false
  option :allow_no_categories, default: false

  def mine(category_id)

    category_id = category_id.to_sym

    category_properties = JSON.parse File.read(ebay_filename_by_category(category_id, 'properties')), symbolize_names: true

    products = Array.new

    start = Time.now

    properties_extractors = Hash[@amazon_etl[category_id][:extractors].empty_if_nil.map { |k, v| [k, category_properties[k] + v] }]

    logger = Logger.new 'log-amazon-mine-by-query.log'

    logger.info 'Start new mining'
    queries = $stdin.readlines.map { |x| x.delete("\n") }.uniq

    queries_in_parallel = options[:use_asins] ? 10 : 3
    products_in_parallel = options[:use_asins] ? 1 : 5

    queries.uniq.peach(queries_in_parallel) do |query|

      (logger.info 'Skipped because product query was empty'; next) if query.strip.length == 0

      logger.info "Looking for #{query}"

      if options[:use_asins]
        products_asins = [query]
      else
        search_url = URI::encode "http://www.amazon.com/s/search-alias=#{@amazon_etl[category_id][:search][:search_alias]}&field-keywords=#{query.gsub '&', ' '}"
        web_text = RestClient.get search_url

        File.open(File.dirname(__FILE__) + "/searches-html/#{query}.html", 'w') { |f| f.write web_text }
        (logger.info 'Skipped because no product were matched by the query'; next) if web_text.include? 'did not match any products'

        html = Nokogiri::HTML web_text
        products_asins = html.css('.productTitle').map { |x| x.attributes['id'].value.split('_')[1] }.take(5)

        (logger.info 'Skipped because no asins were found in the search results'; next) if products_asins.empty?
      end

      amazon_request = {marketplace_id: 'ATVPDKIKX0DER', IdType: 'ASIN'}

      products_asins.each_with_index { |x, i| amazon_request["IdList.Id.#{i+1}"]=x }

      amazon_products = [@mws.products.get_matching_product_for_id(amazon_request)].flatten

      logger.info "Found #{amazon_products.length} products for #{products_asins.length} asins at #{query} search"

      (logger.info 'Skipped because amazon api returned no products'; next) if amazon_products.length == 0

      amazon_products.peach(products_in_parallel) { |x|

        begin

          amazon_product = x.product

          (logger.info "Skipped because product was nil"; next) if amazon_product.nil?

          asin = amazon_product.identifiers.marketplace_asin.asin

          (logger.info 'Skipped because product asin was already gathered'; next) if products.any? { |x| x[:asin] == asin }

          amazon_name = amazon_product.attribute_sets.item_attributes.title

          name_hash = augment_name(amazon_name, category_id, properties_extractors)

          amazon_name = name_hash[:amazon_name]
          original_name = name_hash[:original_name]

          brand = amazon_product.attribute_sets.item_attributes.brand
          model = amazon_product.attribute_sets.item_attributes.model || amazon_product.attribute_sets.item_attributes.partNumber
          features = amazon_product.attribute_sets.item_attributes.feature

          (logger.info "Skipped #{asin} because no sales ranking"; next) if amazon_product.sales_rankings.nil?

          if amazon_product.sales_rankings.sales_rank.kind_of?(Array)
            sales_rank = amazon_product.sales_rankings.sales_rank.min_by { |x| x.rank.to_i }.rank.to_i
          else
            sales_rank = amazon_product.sales_rankings.sales_rank.rank.to_i
          end

          amazon_url = "http://www.amazon.com/product-name/dp/#{asin}"

          (logger.info "Skipped #{asin} because No brand and no model and no sales rank"; next) if brand.nil? || model.nil? || sales_rank.nil?
          (logger.info "Skipped #{asin} because sale rank was above 150000"; next) if sales_rank > 150000

          categories = (Nokogiri::HTML(RestClient.get amazon_url).at('h2:contains("Look for Similar Items by Category")').parent.css('ul li').map { |x| x.css('a').map { |a| a.text }.join('::') } rescue nil)

          allow_no_categories = @amazon_etl[category_id][:allow_no_category]

          (logger.info "Skipped #{asin} because found no categories and allow no categories is #{allow_no_categories}"; next) if (categories.nil? || categories.length == 0) && (!allow_no_categories & !options[:allow_no_categories])

          high_price = @mws.products.get_competitive_pricing_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin
          low_price_new = @mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'New'
          low_price_used = @mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'Used'

          (logger.info "Skipped #{asin} because no price info"; next) if high_price.nil? && low_price_new.nil? && low_price_used.nil?

          logger.info amazon_name

          competitive_pricing_analyze = MathTools.analyze(high_price.listing_price.empty_if_nil.map { |x| x[:price].to_i })
          lowest_offer_new_analyze = MathTools.analyze(low_price_new.listing_price.empty_if_nil.map { |x| x[:price].to_i })
          lowest_offer_used_analyze = MathTools.analyze(low_price_used.listing_price.empty_if_nil.map { |x| x[:price].to_i })

          item_count = [competitive_pricing_analyze, lowest_offer_new_analyze, lowest_offer_used_analyze].compact.inject(0) { |sum, x| sum + x[:count] }


          product = {
              id: asin,
              name: amazon_name,
              original_name: original_name,
              amazon_url: amazon_url,
              brand: brand,
              model: model,
              features: features,
              asin: asin,
              sales_rank: sales_rank,
              item_count: item_count,
              categories: categories,
              price: {},
              competitive_pricing: competitive_pricing_analyze,
              lowest_offer_new: lowest_offer_new_analyze,
              lowest_offer_used: lowest_offer_used_analyze,
          }

          product[:price][:new] = competitive_pricing_analyze[:median] if not competitive_pricing_analyze.nil?
          product[:price][:low_new] = lowest_offer_new_analyze[:median] if not lowest_offer_new_analyze.nil?
          product[:price][:used] = lowest_offer_used_analyze[:median] if not lowest_offer_used_analyze.nil?

          properties_extractors.map { |k, v|
            extracted = v.map { |x| original_name.scan /#{x}/i }.flatten.map(&:downcase)
            product[k]= extracted.first if extracted.any?
          }

          products << product

        rescue Exception => ex
          logger.error "Product name: #{amazon_name}\n Amazon name: #{amazon_name}\n #{ex.message}\n#{ex.backtrace.join("\n ")}"
        end
      }
    end

    products = products.uniq { |x| x[:asin] }

    logger.info "Took: #{(Time.now-start)/60} min"
    number_of_products = products.length

    logger.info "Number of products found is: #{number_of_products}"
    File.open(amazon_filename_by_category(category_id), 'w') { |f| f.write JSON.pretty_generate(products) }

  end

  desc 'Get products using Asin directly', 'No need for searching the text'

  desc 'Fetch top 100 items from amazon', 'Fetch top sellers, top ranked from amazon'

  def top_100(amazon_department_and_category)

    fetch_urls = (1..5).map { |x| "http://www.amazon.com/x/zgbs/#{amazon_department_and_category}?_encoding=UTF8&pg=#{x}" }
    .concat((1..5).map { |x| "http://www.amazon.com/gp/most-gifted/#{amazon_department_and_category}?_encoding=UTF8&pg=#{x}" })
    .concat((1..5).map { |x| "http://www.amazon.com/gp/most-wished-for/#{amazon_department_and_category}?_encoding=UTF8&pg=#{x}" })
    .concat((1..5).map { |x| "http://www.amazon.com/gp/top-rated/#{amazon_department_and_category}?_encoding=UTF8&pg=#{x}" })
    .concat((1..5).map { |x| "http://www.amazon.com/gp/new-releases/#{amazon_department_and_category}?_encoding=UTF8&pg=#{x}" })

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

  desc 'Stream the properties to STDOUT', 'Takes the category id and a list of properties'

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

  desc 'Test the augmentation of names', 'use category_id and name'

  def test_name_augmentation(name, category_id)
    category_id = category_id.to_sym

    category_properties = JSON.parse File.read(ebay_filename_by_category(category_id, 'properties')), symbolize_names: true

    properties_extractors = Hash[@amazon_etl[category_id][:extractors].empty_if_nil.map { |k, v| [k, category_properties[k] + v] }]

    $stdout.puts augment_name(name, category_id, properties_extractors)
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

end

AmazonMining.start