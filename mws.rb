require_relative 'ruby-mws'

mws = MWS.new(:aws_access_key_id => "AKIAIDZUEZILKOGLJNJQ",
              :secret_access_key => "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",
              :seller_id => "A25ONFDA24CSQ8",
              :marketplace_id => "ATVPDKIKX0DER")

products = mws.products.list_matching_products :query => 'Apple iPhone 4 16 GB', :marketplace_id => 'ATVPDKIKX0DER'
asin = Array.new
products.products.each { |x|
  next if x.kind_of?(Array)

  $stdout.puts x

  $stdout.puts x.attribute_sets.item_attributes.title
  asin = x.identifiers.marketplace_asin.asin
  $stdout.puts asin

  $stdout.puts x.sales_rankings.sales_rank.map {|x| x.product_category_id if !x.kind_of?(Array) && x.product_category_id.match(/^\d*$/)} if not x.sales_rankings.nil?

  categories =  mws.products.get_product_categories_for_asin(:marketplace_id => 'ATVPDKIKX0DER', :asin => asin).categories
  $stdout.puts categories

  price = mws.products.get_competitive_pricing_for_asin :marketplace_id => 'ATVPDKIKX0DER',:'ASINList.ASIN.1' => asin

  $stdout.puts price.listing_price

  price = mws.products.get_lowest_offer_listings_for_asin :marketplace_id => 'ATVPDKIKX0DER',:'ASINList.ASIN.1' => asin

  $stdout.puts price.listing_price

}



