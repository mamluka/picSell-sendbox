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

logger = Logger.new('get-ebay-items.log')
finder = Rebay::Finding.new
product_details = Array.new

start = Time.now

(1..1).each do |page|

  begin
    current_page = page
    response = finder.find_items_by_category(categoryId: ARGV[0].to_i, :'paginationInput.entriesPerPage' => 100, :'paginationInput.pageNumber' => current_page, :'itemFilter.name' => 'ListingType', :'itemFilter.value' => 'AuctionWithBIN', sortOrder: 'BidCountMost')

    logger.info response.response

    next if response.results.nil?

    results = response.results

    results.peach(5) do |x|

      begin

        logger.info x

        name = x['title']
        product_details << {
            title: name,
            listing_type: x['listingInfo']['listingType'],
            primary_category: x['primaryCategory']['categoryName'],
            details_url: x['viewItemURL']
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
logger.info "Number of product_details found is: #{product_details.length}"

if product_details.length > 0
  File.open("#{ARGV[1]}.json", 'w') { |f| f.write JSON.pretty_generate(product_details) }
end
