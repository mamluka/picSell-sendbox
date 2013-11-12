require 'rebay'
require 'json'
require 'logger'
require 'rest-client'
require 'peach'
require 'open-uri'
require 'pry'
require 'logger'

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

products = Array.new

start = Time.now

product_ranking = Hash.new

(1..1).each do |page|

  begin
    current_page = page
    response = shopping.find_products(CategoryID: 9355, MaxEntries: 20, PageNumber: current_page, IncludeSelector: 'Details')

    next if response.results.nil?

    results = response.results

    results.each_index { |i| product_ranking[results[i]['ProductID']['Value']] = (10000-((current_page-1)*20+i+1)) }

    results.peach(2) do |x|

      begin

        response = RestClient.get x['DetailsURL']

        response = response.force_encoding('utf-8')

        product_id = x['ProductID']['Value']

        brand = response.scan(/>Brand.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
        model = response.scan(/>Model.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
        family_line = response.scan(/>Family Line.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
        carrier = response.scan(/>Carrier.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
        storage_capacity = response.scan(/>Storage Capacity.+?<font.+?>(.+?)<\/font>/)[0][0].delete(' ') rescue nil

        family_line = family_line.gsub(brand, '') if !brand.nil? && !family_line.nil?

        name = "#{brand} #{family_line} #{model} #{storage_capacity}".squeeze(' ').strip

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

        amazon_products.products.peach(2) { |x|

          begin

            next if x.kind_of?(Array)

            asin = x.identifiers.marketplace_asin.asin
            amazon_name = x.attribute_sets.item_attributes.title

            logger.info "Found amazon name canidate #{amazon_name}"

            next if not (amazon_name =~ /#{storage_capacity}/i && amazon_name =~ /\s#{model}\s/i)

            logger.info "Found amazon name canidate #{amazon_name} to be successful"

            product_categories = x.sales_rankings.sales_rank.map { |x| x.product_category_id.to_i if !x.kind_of?(Array) && x.product_category_id.match(/^\d*$/) }.select { |x| x!= nil } if not x.sales_rankings.nil?

            amazon_url = "http://www.amazon.com/product-name/dp/#{asin}"

            if product_categories.nil? || product_categories.all? { |x| x != 2407749011 && x != 2407748011 }

              amazon_page = open(amazon_url)
              amazon_page_content = amazon_page.read

              amazon_category_section_array = amazon_page_content.scan(/Look for Similar Items by Category(.+?)<\/div>/m)
              if amazon_category_section_array.length == 0
                next
              end

              amazon_category_section = amazon_category_section_array[0][0]

              if !amazon_category_section.include?(2407749011.to_s) && !amazon_category_section.include?(2407748011.to_s)
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

          rescue Exception => ex
            logger.error "Product name: #{name}\n Amazon name: #{amazon_name}\n #{ex.message}\n#{ex.backtrace.join("\n ")}"
          end
        }


        products << {
            name: name,
            details_url: x['DetailsURL'],
            product_id: product_id,
            model: model,
            brand: brand,
            family_line: family_line,
            carrier: carrier,
            storage_capacity: storage_capacity,
            popularity_rank: product_ranking[product_id],
            item_count: (items_by_product.length rescue nil),
            ebay_new_range: (MathTools.percent_range(ebay[:new][:median], 0.1) rescue nil),
            ebay_used_range: (MathTools.percent_range(ebay[:used][:median], 0.1) rescue nil),
            amazon_competitive_pricing: (MathTools.percent_range(amazon.first[:competitive_pricing][:median], 0.1) rescue nil),
            amazon_lowest_offer_used: (MathTools.percent_range(amazon.first[:lowest_offer_used][:median], 0.1) rescue nil),
            amazon_lowest_offer_new: (MathTools.percent_range(amazon.first[:lowest_offer_new][:median], 0.1) rescue nil),
            amazon_lowest_offer_refurbished: (MathTools.percent_range(amazon.first[:lowest_offer_refurbished][:median], 0.1) rescue nil),
            amazon_matched_products: (amazon.map { |x| x[:name] } rescue nil),
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
logger.info "Number of products found is: #{products.length}"

File.open('phones-ebay-products.json', 'w') { |f| f.write JSON.pretty_generate(products) }
