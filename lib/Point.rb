class Point
  
  attr_accessor :x, :y
  
  def initialize(*args)  
    unless args.size <= 2
      raise StandardError, "the Point-initializer takes one Array, two numbers or no Arguments at all." 
    else  
      if args.size == 1 && args[0].class == Array then
        @x = args[0][0]
        @y = args[0][1]
      elsif args.size == 2  
        @x = args[0]
        @y = args[1] 
      else  
        @x = 0
        @y = 0 
      end  
    end  
  end
  
  def +(point)
    Point.new( x + point.x, y + point.y )
  end
  
  def -(point)
    Point.new( x - point.x, y - point.y )
  end
  
  def *(factor)
    Point.new( x*factor, y*factor )
  end
  
  def ==(point)
    if x == point.x && y == point.y then true else false end
  end
  
  def parallel?(point)
    if x*point.y - y*point.x == 0 then true else false end
  end
  
  def null?
    x == 0 && y == 0
  end
  
  def to_array
    [@x, @y]
  end
  
  #redundant?
  def clone
    Point.new( x, y )
  end
end