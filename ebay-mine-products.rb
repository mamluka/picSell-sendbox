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

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

logger = Logger.new('product-data-mining.log')

shopping = Rebay::Shopping.new
finder = Rebay::Finding.new

mapping = YAML.load(File.read(File.dirname(__FILE__) + '/mapping.yml'))

products = Array.new

start = Time.now

product_ranking = Hash.new

category_id = ARGV[0]
(1..ARGV[1].to_i).peach(5) do |page|

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

        extracted_properties = Hash[extracted_properties.map { |k, v| [k.downcase, v] }]

        logger.info "Working on #{name}"

        items_by_product = finder.find_items_by_product({productId: product_id, :'itemFilter.name' => 'ListingType', :'itemFilter.value' => 'AuctionWithBIN'}).results

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
            popularity_rank: product_ranking[product_id],
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
File.open("ebay-#{category_id}.json", 'w') { |f| f.write JSON.pretty_generate(products) }
