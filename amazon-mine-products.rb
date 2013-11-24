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

products = Array.new
start = Time.now
ebay_data = JSON.parse(File.read("ebay-#{ARGV[0]}.json"), :symbolize_names => true)

amazon_etl = YAML.load(File.read(File.dirname(__FILE__) + '/amazon-etl.yml'))
properties_extractors = Hash[amazon_etl[ARGV[0].to_sym][:extractors].map { |k, v| [k, ebay_data.map { |p| (p[:properties][k] rescue nil) }.select { |p| p != nil }.uniq + v] }]

products << properties_extractors

logger = Logger.new 'log-amazon-mine-products.log'

#ebay_data.select { |x| x[:properties].has_key? :UPC }.map { |x| x[:properties][:UPC] }.flatten.each do |upc|
ebay_data.map { |x| x[:name] }.peach(2) do |upc|

  logger.info "Looking for #{upc}"
  #amazon_products = mws.products.list_matching_products :query => upc, :marketplace_id => 'ATVPDKIKX0DER'

  search_url = URI::encode "http://www.amazon.com/s/search-alias=#{amazon_etl[ARGV[0].to_sym][:search][:search_alias]}&field-keywords=#{upc}"
  web_text = RestClient.get search_url

  next if web_text.include? 'did not match any products'

  html = Nokogiri::HTML web_text

  products_asins = html.css('.productTitle').map { |x| x.attributes['id'].value.split('_')[1] }.take(5)

  amazon_request = {marketplace_id: 'ATVPDKIKX0DER', IdType: 'ASIN'}

  products_asins.each_with_index { |x, i| amazon_request["IdList.Id.#{i+1}"]=x }

  amazon_products = mws.products.get_matching_product_for_id(amazon_request)

  next if amazon_products.length == 0

  amazon_products.peach(10) { |x|

    begin
      x = x.product

      next if x.nil?

      asin = x.identifiers.marketplace_asin.asin

      next if products.any? { |x| x[:asin] == asin }

      amazon_name = x.attribute_sets.item_attributes.title
      original_name = amazon_name

      extra_properties = Hash[properties_extractors.map { |k, v|
        logger.info "Checking name #{amazon_name} for #{k}"
        props = v.map { |x| amazon_name.scan /#{x}/i }.flatten
        logger.info "Found #{k} to be #{props}"
        [k, props]
      }]

      properties_extractors.each { |k, v| amazon_name = v.inject(amazon_name) { |name, x| name.split(' ').delete_if { |w| w.downcase == x.downcase }.join(' ') } }

      amazon_name = amazon_etl[ARGV[0].to_sym][:bad_phrases].inject(amazon_name) { |name, x| name.gsub /#{x}/i, '' }
      amazon_name = amazon_etl[ARGV[0].to_sym][:bad_patterns].inject(amazon_name) { |name, x| name.gsub /#{x}/i, '' }
      amazon_name = amazon_etl[ARGV[0].to_sym][:bad_words].inject(amazon_name) { |name, x| name.split(' ').delete_if { |w| w.downcase == x.downcase }.join(' ') }

      brand = x.attribute_sets.item_attributes.brand
      model = x.attribute_sets.item_attributes.model
      sales_rank = (x.sales_rankings.sales_rank.rank.to_i rescue nil)

      amazon_url = "http://www.amazon.com/product-name/dp/#{asin}"

      next if brand.nil? || model.nil? || sales_rank.nil?
      next if sales_rank > 150000

      categories = (Nokogiri::HTML(RestClient.get amazon_url).at('h2:contains("Look for Similar Items by Category")').parent.css('ul li').map { |x| x.css('a').map { |a| a.text }.join('::') } rescue nil)


      next if categories.nil? || categories.length == 0

      high_price = mws.products.get_competitive_pricing_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin
      low_price_new = mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'New'
      low_price_used = mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin, ItemCondition: 'Used'

      next if high_price.nil? && low_price_new.nil? && low_price_used.nil?

      logger.info amazon_name

      products << {
          id: asin,
          name: amazon_name,
          original_name: original_name,
          amazon_url: amazon_url,
          brand: brand,
          model: model,
          asin: asin,
          sales_rank: sales_rank,
          extra_properties: extra_properties,
          categories: categories,
          competitive_pricing: MathTools.analyze(ArrayUtils.empty_if_nil(high_price.listing_price).map { |x| x[:price].to_i }),
          lowest_offer_new: MathTools.analyze(ArrayUtils.empty_if_nil(low_price_new.listing_price).map { |x| x[:price].to_i }),
          lowest_offer_used: MathTools.analyze(ArrayUtils.empty_if_nil(low_price_used.listing_price).map { |x| x[:price].to_i }),
      }

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

products = products.group_by { |x| x[:name] }.map { |k, v| v.min_by { |x|
  p =x[:lowest_offer_used][:median] if !x[:lowest_offer_used].nil?
  p =x[:lowest_offer_new][:median] if !x[:lowest_offer_new].nil?
  p =x[:competitive_pricing][:median] if !x[:competitive_pricing].nil?
  p
} }

File.open("amazon-#{ARGV[0]}-uniq.json", 'w') { |f| f.write JSON.pretty_generate(products) }