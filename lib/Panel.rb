
require File.expand_path( File.dirname(__FILE__) + "/Point.rb" )
# A Panel represents a single Panel on the page of a comic book.
# the page should call its "arrange" method do position it somewhere.
class Panel
  
  attr_accessor :attributes, :parentpage, :text, :size, :origin
  
  def initialize( parent )
    @attributes = Hash.new
    @parentpage = parent # the page that this panel belongs to
    @text = Array.new
    @size = Point.new
    @origin = Point.new
  end
  
  def arrange!
    if self == parentpage.panels.first then # we are dealing with the first panel on a page here
      origin.x = parentpage.margin_left
      origin.y = parentpage.margin_top
      self.setSize!
    elsif self.float? then
      self.float_h( self.previous ) # position a panel on the right side of it's predecessor
    else # panel not floating
      self.float_v( self.previous ) # position a panel below its predecessor
    end 
    parentpage.panels.each do |p|
      if p != self && self.intersectsWith?( p ) then # does it intersect with anything?
        self.origin.y = p.y # in this case move it down below the "offending" panel
        begin    
          slideup   = self.slide_up!       
          slideleft = self.slide_left! 
        end while slideup || slideleft
      end
    end  
  end
  
  def float? # by default, panels float (are positioned to the right of their predecessor)
    attributes[:float]
  end

# ----------------------------------------------
  
  def float_h( base ) # float self (position in x-direction) relative to 'base'  
    origin.y = base.origin.y
    origin.x = base.x
    if base.x + attributes[:width] > parentpage.parent.defaults[:pagewidth] - parentpage.margin_right then # the panel dosn't fit on the page horizontally; it has to be moved to the next line.      
      self.float_v( base )  
    end
    self.setSize!
    begin    
      slideup   = self.slide_up!       
      slideleft = self.slide_left! 
    end while slideup || slideleft
  end
  
  def float_v( base ) # float self (position in y-direction) relative to 'base'
    origin.x = base.origin.x
    origin.y = base.y
    self.setSize!
    begin     
      slideleft = self.slide_left!      
      slideup   = self.slide_up!        
    end while slideup || slideleft
  end

# ----------------------------------------------
  
  def slide_up!
    # get the panel with the next smaller y-coordinate
    list = parentpage.panels.reject{ |panel| panel.origin.y >= self.origin.y || panel.origin.y == 0 }
    
    if list.size > 0 then
      newbase = list.sort!{ |p1,p2|  
        if p1.y >= self.origin.y then
          a = p1.origin.y
        else 
          a = p1.y
        end
        if p2.y >= self.origin.y then
          b = p2.origin.y
        else 
          b = p2.y
        end
        a <=> b 
      }.last
      
      # position a copy of self relative to it
      c = self.clone
      
      if self.origin.y <= newbase.y then
        c.origin.y = newbase.origin.y
      else
        c.origin.y = newbase.y
      end
      
      # does it intersect with anything?
      parentpage.panels.each do |p|
        if p != self && c.intersectsWith?( p ) then # yes, it does: no sliding to be done. return false.
          return false
        end
      end
      
      # no, it doesn't: adopt the new coordinates
      self.origin.y = c.origin.y
      return true
      
    else
      return false
    end
  end
  
  def slide_left!
    # get the panel with the next smaller y-coordinate
    list = parentpage.panels.reject{ |panel| panel.origin.x >= self.origin.x || panel.origin.x == 0 }

    if list.size > 0 then
      newbase = list.sort!{ |p1,p2|  
        if p1.x >= self.origin.x then
          a = p1.origin.x
        else 
          a = p1.x
        end
        if p2.x >= self.origin.x then
          b = p2.origin.x
        else 
          b = p2.x
        end
        a <=> b 
      }.last
      
      # position a copy of self relative to it
      c = self.clone
      
      if self.origin.x <= newbase.x then
        c.origin.x = newbase.origin.x
      else
        c.origin.x = newbase.x
      end

      # does it intersect with anything?
      parentpage.panels.each do |p|
        if p != self && c.intersectsWith?( p ) then # yes, it does: no sliding up. return false.
          return false
        end
      end
      
      # no, it doesn't: adopt the new coordinates
      self.origin.x = c.origin.x
      return true

    else
      return false
    end
  end
  
  # when a panel is "trapped" on three sides, it may be necessary to slide it down until there is enough space for it.
  # the neccessity to slide right may in fact occur, but it shouldn't for the purposes of common comic reading order.
  def slide_down!
  end  
  
  
  def setSize!
    size.x = attributes[:width]
    size.y = attributes[:height]
    if size.x == 0 then size.x = parentpage.parent.defaults[:pagewidth] - parentpage.margin_right - origin.x end
    if size.y == 0 then size.y = parentpage.parent.defaults[:pageheight] - parentpage.margin_bottom - origin.y end
  end
  
  def previous
    i = parentpage.panels.index(self) - 1
    if i < 0 then
      nil
    else
      parentpage.panels[ i ]
    end
  end
  
  def intersectsWith?( panel )
    if panel.attributes[:type].to_sym == :overlay then
      false
    else
      [x, panel.x].min > [origin.x, panel.origin.x].max && [y, panel.y].min > [origin.y, panel.origin.y].max
    end
  end
  
  def x # Max extension of this panel in x-direction
    origin.x + size.x
  end
  
  def y # Max extension of this panel in y-direction
    origin.y + size.y
  end
  
  def clone
    cl = Panel.new( self.parentpage )
    cl.attributes = self.attributes.clone
    cl.text = self.text
    cl.size = self.size.clone
    cl.origin = self.origin.clone
    return cl
  end
  
end