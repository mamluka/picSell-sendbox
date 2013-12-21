category=$1
pageCount=$2

./ebay-mining-tool.rb mine_by_category $category $pageCount
./ebay-mining-tool.rb generate-matches ebay-$category.json $category > pre-matched-$category.json
./amazon-mining-tool.rb match pre-matched-$category.json $category > matched-$category.json
./amazon-mining-tool.rb extract-asins matched-$category.json > asins/$category
cat asins/$category | ./amazon-mining-tool.rb mine $category --use-asins --allow-no-categories --allow-any-sales-ranking
./pipe-tool.rb combine ebay-$category.json amazon-$category.json matched-$category.json > combined-$category.json
./pipe-tool.rb mash combined-$category.json $category > indexable-$category.json
./product-indexing-tool.rb index indexable-$category.json
