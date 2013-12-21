require 'json'
require 'tf_idf'
require 'pry'

ebay_data = JSON.parse File.read('ebay-9355.json'), symbolize_names: true
amazon_data = JSON.parse File.read('amazon-9355.json'), symbolize_names: true


ebay_top_tf = TfIdf.new(ebay_data.map { |x| x[:name].downcase.split(' ') }).idf
ebay_good_words = ebay_top_tf.select { |k, v| v < 1.5 }.map { |k, v| k }

ebay_good_words << ebay_data.map { |x| (x[:properties][:Model].downcase.split(' ')) }.flatten
ebay_good_words << ebay_data.map { |x| (x[:properties][:Brand].downcase.split(' ')) }.flatten
ebay_good_words << ebay_data.map { |x| (x[:properties][:Storage].downcase.split(' ') rescue nil) }.flatten

ebay_good_words.flatten!



amazon_tf_idf =TfIdf.new(amazon_data.map { |x| x[:name].downcase.split(' ') }).tf_idf

new_amazon_names = amazon_tf_idf.map { |x|
  x.map { |k, v|
    next k if v > 0.25 || ebay_good_words.include?(k)
    next "[#{k}:#{v.round(2)}]"
  }.join(' ')
}

$stdout.puts new_amazon_names.select { |x| !x.nil? }
