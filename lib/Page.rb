
# note to self; should I require Panel.rb?


# Page represents a page in a comic-book. It has lots of panels
class Page

  attr_accessor :attributes, :panels, :parent

  def initialize
    @attributes = Hash.new
    @panels = Array.new
  end
  
  def arrange!
    panels.each do |panel| 
      panel.arrange! 
    end
    return self
  end

  def margin_left # on even pages, the left margin is the 'outer' margin
    if self.even? then
      parent.defaults[:aussensteg]
    else
      parent.defaults[:bundsteg]
    end 
  end

  def margin_top
    parent.defaults[:kopfsteg]
  end

  def margin_right # on even pages, the right margin is the 'inner' margin
    if self.even? then
      parent.defaults[:bundsteg]
    else
      parent.defaults[:aussensteg]
    end
  end

  def margin_bottom
    parent.defaults[:fusssteg]
  end

  def even?
    if attributes[:id].to_i % 2 == 0 then
      true
    else
      false
    end
  end

  def include?(point)
    point.x >= self.margin_left && point.x <= self.margin_right && point.y >= self.margin_top && point.y <= self.margin_bottom
  end
  
end