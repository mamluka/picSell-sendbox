module MWS
  module API

    class Products < Base
      def_request [:list_matching_products, :list_matching_products_by_next_token],
                  :verb => :post,
                  :uri => '/Products/2011-10-01',
                  :version => '2011-10-01',
                  :mods => [
                      lambda { |r| r.products = r.products.product if not r.products.nil? }
                  ]

      def_request [:get_product_categories_for_asin],
                  :verb => :post,
                  :uri => '/Products/2011-10-01',
                  :version => '2011-10-01',
                  :mods => [
                      lambda { |r|
                        if r.self.kind_of?(Array)
                          r.category = {id: r.self.first.product_category_id, name: r.self.first.product_category_name} if not r.self.nil?
                        else
                          r.category = {id: r.self.product_category_id, name: r.self.product_category_name} if not r.self.nil?
                        end

                      }
                  ]

      def_request [:get_competitive_pricing_for_asin],
                  :verb => :post,
                  :uri => '/Products/2011-10-01',
                  :version => '2011-10-01',
                  :mods => [
                      lambda { |r|
                        next if r.product.competitive_pricing.competitive_prices.nil?

                        competitive_price = r.product.competitive_pricing.competitive_prices.competitive_price

                        if not competitive_price.kind_of?(Array)
                          competitive_price = [competitive_price]
                        end
                        r.listing_price=Array.new
                        r.landed_price=Array.new

                        competitive_price.each do |list|
                          r.listing_price << {
                              condition: list.condition,
                              subcondition: list.subcondition,
                              price: list.price.listing_price.amount

                          }

                          r.landed_price << {
                              condition: list.condition,
                              subcondition: list.subcondition,
                              price: list.price.landed_price.amount

                          }
                        end
                      }
                  ]

      def_request [:get_lowest_offer_listings_for_asin],
                  :verb => :post,
                  :uri => '/Products/2011-10-01',
                  :version => '2011-10-01',
                  :mods => [
                      lambda { |r|

                        lowest_offer_listing = r.product.lowest_offer_listings.lowest_offer_listing

                        if not lowest_offer_listing.kind_of?(Array)
                          lowest_offer_listing = [lowest_offer_listing]
                        end

                        r.listing_price=Array.new
                        r.landed_price=Array.new

                        lowest_offer_listing.each do |list|
                          r.listing_price << {
                              condition: list.qualifiers.item_condition,
                              subcondition: list.qualifiers.item_subcondition,
                              price: list.price.listing_price.amount

                          }

                          r.landed_price << {
                              condition: list.qualifiers.item_condition,
                              subcondition: list.qualifiers.item_subcondition,
                              price: list.price.landed_price.amount

                          }
                        end
                      }
                  ]

    end
  end
end