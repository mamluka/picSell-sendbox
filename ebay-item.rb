require 'rebay'
require 'json'
require 'logger'
require 'rest-client'
require 'peach'
require 'open-uri'
require 'pry'
require 'logger'
require 'yaml'

require_relative 'math-tools'
require_relative 'ruby-mws'

class ArrayUtils
  def self.empty_if_nil(arr)
    return [] if arr.nil?
    arr
  end
end

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

logger = Logger.new('product-data-mining.log')

mws = MWS.new(:aws_access_key_id => "AKIAIDZUEZILKOGLJNJQ",
              :secret_access_key => "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",
              :seller_id => "A25ONFDA24CSQ8",
              :marketplace_id => "ATVPDKIKX0DER")

shopping = Rebay::Shopping.new
finder = Rebay::Finding.new

mapping = YAML.load(File.read(File.dirname(__FILE__) + '/mapping.yml'))

products = Array.new

start = Time.now

product_ranking = Hash.new

category_id = ARGV[0]

(1..ARGV[1].to_i).each do |page|

  begin
    current_page = page

    response = shopping.find_products(CategoryID: category_id, MaxEntries: 20, PageNumber: current_page, IncludeSelector: 'Details')

    next if response.results.nil?

    results = response.results

    results.each_index { |i| product_ranking[results[i]['ProductID']['Value']] = (10000-((current_page-1)*20+i+1)) }

    results.peach(5) do |x|

      begin

        response = RestClient.get x['DetailsURL']

        response = response.force_encoding('utf-8')

        product_id = x['ProductID']['Value']

        properties = mapping[:ebay_details_mapping][category_id.to_sym]

        extracted_properties = Array.new
        properties[:properties].each do |prop|
          extracted = (response.scan(/>#{prop}.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil)
          extracted_properties << {name: prop, value: extracted} if not extracted.nil?
        end

        name = extracted_properties
        .select { |x| !x.nil? }
        .select { |x|
          if not properties[:exclude_from_name].nil?
            !properties[:exclude_from_name].include?(x[:name])
          else
            true
          end
        }
        .map { |x| x[:value] }
        .uniq.join(' ')
        .split(' ')
        .uniq
        .join(' ')

        logger.info "Working on #{name}"

        items_by_product = finder.find_items_by_product({productId: product_id, :'itemFilter.name' => 'ListingType', :'itemFilter.value' => 'AuctionWithBIN'}).results

        ebay = nil
        amazon = Array.new

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

        amazon_products = mws.products.list_matching_products :query => name, :marketplace_id => 'ATVPDKIKX0DER'

        halt = false

        amazon_products.products.each { |x|

          begin

            next if x.kind_of?(Array)

            next if halt

            asin = x.identifiers.marketplace_asin.asin
            amazon_name = x.attribute_sets.item_attributes.title

            product_categories = x.sales_rankings.sales_rank.map { |x| x.product_category_id.to_i if !x.kind_of?(Array) && x.product_category_id.match(/^\d*$/) }.select { |x| x!= nil } if not x.sales_rankings.nil?
            amazon_url = "http://www.amazon.com/product-name/dp/#{asin}"

            allows_categories = mapping[:amazon_categories_mapping][category_id.to_sym]

            if product_categories.nil? || (product_categories & allows_categories).length == 0

              amazon_page = open(amazon_url)
              amazon_page_content = amazon_page.read

              amazon_category_section_array = amazon_page_content.scan(/Look for Similar Items by Category(.+?)<\/div>/m)
              if amazon_category_section_array.length == 0
                next
              end

              amazon_category_section = amazon_category_section_array[0][0]

              if  allows_categories.all? { |x| amazon_category_section.include? x.to_s }
                next
              end
            end


            high_price = mws.products.get_competitive_pricing_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin
            low_price = mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER', :'ASINList.ASIN.1' => asin

            amazon << {
                name: amazon_name,
                amazon_url: amazon_url,
                competitive_pricing: MathTools.analyze(ArrayUtils.empty_if_nil(high_price.listing_price).map { |x| x[:price].to_i }),
                lowest_offer_new: MathTools.analyze(ArrayUtils.empty_if_nil(low_price.listing_price).select { |x| x[:condition] =='New' }.map { |x| x[:price].to_i }),
                lowest_offer_used: MathTools.analyze(ArrayUtils.empty_if_nil(low_price.listing_price).select { |x| x[:condition] =='Used' }.map { |x| x[:price].to_i }),
                lowest_offer_refurbished: MathTools.analyze(ArrayUtils.empty_if_nil(low_price.listing_price).select { |x| x[:condition] =='Refurbished' }.map { |x| x[:price].to_i })

            }

            halt = true

          rescue Exception => ex
            logger.error "Product name: #{name}\n Amazon name: #{amazon_name}\n #{ex.message}\n#{ex.backtrace.join("\n ")}"
          end
        }


        ebay_new_range = (MathTools.percent_range(ebay[:new][:median], 0.1) rescue nil)
        ebay_used_range = (MathTools.percent_range(ebay[:used][:median], 0.1) rescue nil)
        amazon_competitive_price = (MathTools.percent_range(amazon.first[:competitive_pricing][:median], 0.1) rescue nil)
        amazon_lowest_offer_used = (MathTools.percent_range(amazon.first[:lowest_offer_used][:median], 0.1) rescue nil)
        amazon_lowest_offer_new = (MathTools.percent_range(amazon.first[:lowest_offer_new][:median], 0.1) rescue nil)

        new_deviation_warning = (MathTools.deviation_warning(ebay[:new][:median], amazon.first[:competitive_pricing][:median], 20) rescue nil)
        used_deviation_warning = (MathTools.deviation_warning(ebay[:used][:median], amazon.first[:lowest_offer_used][:median], 20) rescue nil)
        new_lowest_offer_new_deviation_warning = (MathTools.deviation_warning(ebay[:new][:median], amazon.first[:lowest_offer_new][:median], 20) rescue nil)
        new_lowest_offer_used_deviation_warning = (MathTools.deviation_warning(ebay[:new][:median], amazon.first[:lowest_offer_used][:median], 20) rescue nil)

        products << {
            name: name,
            details_url: x['DetailsURL'],
            product_id: product_id,
            properties: extracted_properties,
            popularity_rank: product_ranking[product_id],
            item_count: (items_by_product.length rescue nil),
            ebay_new_range: ebay_new_range,
            ebay_used_range: ebay_used_range,
            amazon_competitive_pricing: amazon_competitive_price,
            amazon_lowest_offer_used: amazon_lowest_offer_used,
            amazon_lowest_offer_new: amazon_lowest_offer_new,
            amazon_lowest_offer_refurbished: (MathTools.percent_range(amazon.first[:lowest_offer_refurbished][:median], 0.1) rescue nil),
            amazon_matched_products: (amazon.map { |x| x[:name] } rescue nil),
            ebay_amazon_new_price_range_problem: new_deviation_warning.nil? ? nil : "ebay_new/amazon_competitive_pricing price diviates: #{new_deviation_warning}%",
            ebay_amazon_used_price_range_problem: used_deviation_warning.nil? ? nil : "ebay_used/lowest_offer_used price diviates: #{used_deviation_warning}%",
            ebay_amazon_new_lowest_offer_new_price_range_problem: new_lowest_offer_new_deviation_warning.nil? ? nil : "ebay_new/lowest_offer_new price diviates: #{new_lowest_offer_new_deviation_warning}%",
            ebay_amazon_new_lowest_offer_used_price_range_problem: new_lowest_offer_used_deviation_warning.nil? ? nil : "ebay_new/lowest_offer_used price diviates: #{new_lowest_offer_used_deviation_warning}%",
            ebay: ebay,
            amazon: amazon
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

number_amazon_matches = products.count { |x| x[:amazon_matched_products].length > 0 }

logger.info "Hits on amazon #{(number_amazon_matches/number_of_products.to_f*100).round(0)}%"

File.open('phones-ebay-products.json', 'w') { |f| f.write JSON.pretty_generate(products) }
