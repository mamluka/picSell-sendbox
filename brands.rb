require 'semantics3'
require 'json'

sem3 = Semantics3::Products.new('SEM3BA39D5412E0CC28BEDE6AAD615E603D2', 'Mzc1MjMwZDdlZGY0OGIwMmYxMzk1ODA1MmU4MTYxZTQ')

products = Array.new

while products.length < 2000

  sem3.products_field('cat_id', ARGV[0])
  sem3.products_field('offset', products.length)

  results = sem3.get_products

  results["results"].each do |f|
    products << {
        name: f['name'],
        brand: f['brand'],
        model: f['model']
    }
  end

  $stdout.puts products.length
end

products.select { |p| !p[:brand].nil? }.map { |p| p[:brand] }.uniq.each { |p| $stdout.puts p }