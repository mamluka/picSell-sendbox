class MathTools
  def self.analyze(arr)

    return nil if arr.length == 0

    total = arr.inject(:+)
    len = arr.length
    sorted = arr.sort

    {
        lowest: arr.min,
        highest: arr.max,
        count: arr.length,
        average: total.to_f / len,
        median: len % 2 == 1 ? sorted[len/2] : (sorted[len/2 - 1] + sorted[len/2]).to_f / 2
    }
  end
end

