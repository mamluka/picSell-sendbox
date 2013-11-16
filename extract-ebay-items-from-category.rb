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

mws = MWS.new(:aws_access_key_id => "AKIAIDZUEZILKOGLJNJQ",
              :secret_access_key => "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",
              :seller_id => "A25ONFDA24CSQ8",
              :marketplace_id => "ATVPDKIKX0DER")

shopping = Rebay::Shopping.new
finder = Rebay::Finding.new

product_details = Array.new

start = Time.now

(1..1).each do |page|

  begin
    current_page = page
    response = shopping.find_products(CategoryID: ARGV[0].to_i, MaxEntries: 20, PageNumber: current_page, IncludeSelector: 'Details')

    next if response.results.nil?

    results = response.results

    results.peach(5) do |x|

      begin

        product_details << {
            product: x,
            details_url: x['DetailsURL']
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

File.open("#{ARGV[1]}.json", 'w') { |f| f.write JSON.pretty_generate(product_details) }
