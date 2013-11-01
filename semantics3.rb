require 'semantics3'
require 'json'
require 'logger'

logger = Logger.new(STDOUT)

sem3 = Semantics3::Products.new('SEM3BA39D5412E0CC28BEDE6AAD615E603D2', 'Mzc1MjMwZDdlZGY0OGIwMmYxMzk1ODA1MmU4MTYxZTQ')

products = Array.new

File.readlines('brands').each do |brand|
  brand = brand.strip

  logger.info "Start looking for #{brand}"
  counter = 0

  while counter < 100

    sem3.products_field('cat_id', 20773)
    sem3.products_field('offset', counter)
    sem3.products_field('brand', brand)

    response = sem3.get_products

    p response

    result = response['results']
    break if result.nil?

    result.each do |f|
      products << {
          name: f['name'],
          brand: f['brand'],
          model: f['model']
      }
    end

    counter = counter + result.length

    logger.info counter
  end
end


File.open('products.json', 'w') { |f| f.write JSON.pretty_generate(products) }