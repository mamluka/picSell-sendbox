class MathTools
  def self.analyze(arr)
    return nil if arr.length == 0

    total = arr.inject(:+)
    len = arr.length
    sorted = arr.sort

    median = len % 2 == 1 ? sorted[len/2] : (sorted[len/2 - 1] + sorted[len/2]).to_f / 2
    {
        lowest: arr.min,
        highest: arr.max,
        count: arr.length,
        average: total.to_f / len,
        median: median,
        percent_range_10: percent_range(median, 0.1),
        percent_range_20: percent_range(median, 0.2)
    }

  end

  def self.percent_range(value, range)
    [(value*(1-range)).round(0), (value*(1+range)).round(0)]
  end

  def self.deviation_warning(first, second, tolerance)
    ratio = ((first/second)*100).round(0)

    if (ratio) < (100-tolerance) || (ratio) > (100+tolerance)
      (ratio-100).abs
    else
      nil
    end
  end
end

