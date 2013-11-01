require 'semantics3'

sem3 = Semantics3::Products.new('SEM3BA39D5412E0CC28BEDE6AAD615E603D2', 'Mzc1MjMwZDdlZGY0OGIwMmYxMzk1ODA1MmU4MTYxZTQ')

sem3.categories_field('parent_cat_id', 4992)
sem3.get_categories['results'].each do |s|
  $stdout.puts s['cat_id']
end