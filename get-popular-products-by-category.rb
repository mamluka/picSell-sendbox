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
shopper = Rebay::Shopping.new

response = shopper.find_popular_items(CategoryID: ARGV[0])




