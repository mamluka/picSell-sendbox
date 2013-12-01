require 'rebay'
require 'json'
require 'logger'
require 'rest-client'
require 'peach'
require 'open-uri'
require 'pry'
require 'logger'
require 'yaml'
require 'nokogiri'
require 'open-uri'
require 'securerandom'

require_relative 'math-tools'
require_relative 'ruby-mws'

class ArrayUtils
  def self.empty_if_nil(arr)
    return [] if arr.nil?
    arr
  end
end



mws = MWS.new(:aws_access_key_id => "AKIAIDZUEZILKOGLJNJQ",
              :secret_access_key => "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",
              :seller_id => "A25ONFDA24CSQ8",
              :marketplace_id => "ATVPDKIKX0DER")

category_id = ARGV[0].to_sym

products = Array.new
all_products_original_name = Array.new

start = Time.now
ebay_data = JSON.parse(File.read("ebay-#{ARGV[0]}.json"), :symbolize_names => true)

amazon_etl = YAML.load(File.read(File.dirname(__FILE__) + '/amazon-etl.yml'))
properties_extractors = Hash[amazon_etl[category_id][:extractors].map { |k, v| [k, ebay_data.map { |p| (p[:properties][k] rescue nil) }.select { |p| p != nil }.uniq + v] }]

logger = Logger.new 'log-amazon-mine-products.log'

#ebay_data.select { |amazon_product| amazon_product[:properties].has_key? :UPC }.map { |amazon_product| amazon_product[:properties][:UPC] }.flatten.each do |query|

logger.info 'Start new mining'
ebay_data.map { |x| x[:name] }.concat(ebay_data.map { |x| "#{x[:brand]} #{x[:'family line']}" }).uniq.peach(3) do |query|

  (logger.info 'Skipped because product query was empty'; next) if query.strip.length == 0

  logger.info "Looking for #{query}"
  #amazon_products = mws.products.list_matching_products :query => query, :marketplace_id => 'ATVPDKIKX0DER'

  search_url = URI::encode "http://www.amazon.com/s/search-alias=#{amazon_etl[category_id][:search][:search_alias]}&field-keywords=#{query.gsub '&', ' '}"

  web_text = RestClient.get search_url

  File.open(File.dirname(__FILE__) + "/searches-html/#{query}.html", 'w') { |f| f.write web_text }

  (logger.info 'Skipped because no product were matched by the query'; next) if web_text.include? 'did not match any products'

  html = Nokogiri::HTML web_text

  products_asins = html.css('.productTitle').map { |x| x.attributes['id'].value.split('_')[1] }.take(5)

  (logger.info 'Skipped because no asins were found in the search results'; next) if products_asins.empty?

  amazon_request = {marketplace_id: 'ATVPDKIKX0DER', IdType: 'ASIN'}

  products_asins.each_with_index { |x, i| amazon_request["IdList.Id.#{i+1}"]=x }

  amazon_products = mws.products.get_matching_product_for_id(amazon_request)

  logger.info "Found #{amazon_products.length} products for #{products_asins.length} asins at #{query} search"

  (logger.info 'Skipped because amazon api returned no products'; next) if amazon_products.length == 0

  amazon_products.peach(5) { |x|

    begin

      amazon_product = x.product

      (logger.info "Skipped because product was nil"; next) if amazon_product.nil?

      asin = amazon_product.identifiers.marketplace_asin.asin

      (logger.info 'Skipped because product asin was already gathered'; next) if products.any? { |x| x[:asin] == asin }

      amazon_name = amazon_product.attribute_sets.item_attributes.title
      original_name = amazon_name

      all_products_original_name << original_name

      properties_extractors.each { |k, v| amazon_name = v.inject(amazon_name) { |name, x| name.split(' ').delete_if { |w| w.downcase == x.downcase }.join(' ') } }

      amazon_name = amazon_etl[category_id][:bad_phrases].empty_if_nil.inject(amazon_name) { |name, x| name.gsub /#{x}/i, '' }
      amazon_name = amazon_etl[category_id][:bad_patterns].empty_if_nil.inject(amazon_name) { |name, x| name.gsub /#{x}/i, '' }
      amazon_name = amazon_etl[category_id][:bad_words].empty_if_nil.inject(amazon_name) { |name, x| name.split(' ').delete_if { |w| w.downcase == x.downcase }.join(' ') }

      brand = amazon_product.attribute_sets.item_attributes.brand
      model = amazon_product.attribute_sets.item_attributes.model || amazon_product.attribute_sets.item_attributes.partNumber

      (logger.info "Skipped because no sales ranking"; next) if amazon_product.sales_rankings.nil?

      if amazon_product.sales_rankings.sales_rank.kind_of?(Array)
        sales_rank = amazon_product.sales_rankings.sales_rank.min_by { |x| x.rank.to_i }.rank.to_i
      else
        sales_rank = amazon_product.sales_rankings.sales_rank.rank.to_i
      end

      amazon_url = "http://www.amazon.com/product-name/dp/#{asin}"

      (logger.info "Skipped #{asin} because No brand and no model and no sales rank"; next) if brand.nil? || model.nil? || sales_rank.nil?
      (logger.info "Skipped #{asin} because sale rank was above 150000"; next) if sales_rank > 150000

      categories = (Nokogiri::HTML(RestClient.get amazon_url).at('h2:contains("Look for Similar Items by Category")').parent.css('ul li').map { |x| x.css('a').map { |a| a.text }.join('::') } rescue nil)
      (logger.info "Skipped #{asin} because found no categories and allow no categories is #{amazon_etl[category_id][:allow_no_category]}"; next) if (categories.nil? || categories.length == 0) && !amazon_etl[category_id][:allow_no_category]

      high_price = mws.products.get_competitive_pricing_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin
      low_price_new = mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'New'
      low_price_used = mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'Used'

      (logger.info "Skipped #{asin} because no price info"; next) if high_price.nil? && low_price_new.nil? && low_price_used.nil?

      logger.info amazon_name

      competitive_pricing_analyze = MathTools.analyze(ArrayUtils.empty_if_nil(high_price.listing_price).map { |x| x[:price].to_i })
      lowest_offer_new_analyze = MathTools.analyze(ArrayUtils.empty_if_nil(low_price_new.listing_price).map { |x| x[:price].to_i })
      lowest_offer_used_analyze = MathTools.analyze(ArrayUtils.empty_if_nil(low_price_used.listing_price).map { |x| x[:price].to_i })

      item_count = [competitive_pricing_analyze, lowest_offer_new_analyze, lowest_offer_used_analyze].compact.inject(0) { |sum, x| sum + x[:count] }


      product = {
          id: asin,
          name: amazon_name,
          original_name: original_name,
          amazon_url: amazon_url,
          brand: brand,
          model: model,
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
File.open("amazon-#{ARGV[0]}.json", 'w') { |f| f.write JSON.pretty_generate(products) }

File.open("amazon-#{ARGV[0]}-filtered-out.log", 'w') { |f| (products.map { |x| x[:original_name] } - all_products_original_name).each { |x| f.puts x } }