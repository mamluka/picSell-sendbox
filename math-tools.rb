class MathTools
  def self.analyze(arr)
    total = arr.inject(:+)
    len = arr.length
    sorted =  arr.sort

    {
        lowest: arr.min,
        highest: arr.max,
        total: total,
        len: arr.length,
        average: total.to_f / len,
        median: len % 2 == 1 ? sorted[len/2] : (sorted[len/2 - 1] + sorted[len/2]).to_f / 2
    }
  end
end

