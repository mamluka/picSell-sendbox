category=$1

./ebay-mining-tool.rb mine_by_category $category 5
./ebay-mining-tool.rb generate-matches ebay-phones.json $category > pre-matched-$category.json
./amazon-mining-tool.rb match pre-matched-phones.json phones > matched-$category.json
./amazon-mining-tool.rb extract-asins matched-$category.json > asins/$category
./pipe-tool.rb combine ebay-$category.json amazon-$category.json matched-$category.json > combined-$category.json
./pipe-tool.rb mash combined-$category.json $category > indexable-$category.json
./product-indexing-tool.rb index indexable-$category.json
