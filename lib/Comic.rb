
require 'yaml'
require 'hpricot'
require 'appscript'
require 'RMagick'
include Appscript
include Magick

require File.expand_path( File.dirname(__FILE__) + "/Page.rb" )
require File.expand_path( File.dirname(__FILE__) + "/Panel.rb" )
require File.expand_path( File.dirname(__FILE__) + "/Point.rb" )

# define comic structure
class Comic
  
  attr_accessor :defaults, :pages
  
  # initializer: parse comic-xml-file into local structure
  def initialize( file )
    @defaults = Hash.new
    @pages = Array.new
    
    hpricotfile = Hpricot(open(file))
    
    # parse comic-defaults (page size, margins...)
    hpricotfile.search("defaults").each do |defaults|
      defaults.attributes.each do |key, value|
        unit = value.slice!(/\D*$/) # strip unit – and ignore it for now.
        if key == "id" then
          @defaults[key.to_sym] = value.to_s
        else
          @defaults[key.to_sym] = value.to_f
        end
      end
      @defaults[:content_width] = @defaults[:pagewidth] - @defaults[:aussensteg] - @defaults[:bundsteg]
      @defaults[:content_height] = @defaults[:pageheight] - @defaults[:kopfsteg] - @defaults[:fusssteg]
      @defaults[:panel_width] = @defaults[:content_width] / @defaults[:panelsperrow]
      @defaults[:panel_height] = @defaults[:content_height] / @defaults[:panelspercol]
    end
    
    # parse the content of each page: panels with speech-bubbles and such
    hpricotfile.search("page").each do |page|
      currentPage = Page.new
      currentPage.parent = self
      if page.at("description") then currentPage.attributes[:description] = page.at("description").inner_html.strip end
      currentPage.attributes[:id] = page.attributes.fetch("id").to_i

      page.search("panel").each do |panel|
        currentPanel = Panel.new(currentPage)
        if panel.at("description") then currentPanel.attributes[:description] = panel.at("description").inner_html.strip end
        panel.attributes.each do |key, value|
          currentPanel.attributes[key.to_sym] = value
        end
        unless currentPanel.attributes.has_key?(:type) then
          currentPanel.attributes[:type] = :default
        end
        # set panel float behaviour
        if currentPanel.attributes.has_key?(:float) then
          if currentPanel.attributes[:float] == "true" then
            currentPanel.attributes[:float] = true
          else
            currentPanel.attributes[:float] = false
          end
        else
          currentPanel.attributes[:float] = true
        end
        # set panel width
        if currentPanel.attributes.has_key?(:width) then
          unit = currentPanel.attributes[:width].slice!(/\D*$/)
          if unit == "x" then
            currentPanel.attributes[:width] = currentPanel.attributes[:width].to_f * @defaults[:panel_width]
          elsif unit == "max" then
            currentPanel.attributes[:width] = 0 # deal with this case later
          else
            currentPanel.attributes[:width] = currentPanel.attributes[:width].to_f
          end
        else
          currentPanel.attributes[:width] = @defaults[:panel_width]
        end
        # ...and height
        if currentPanel.attributes.has_key?(:height) then
          unit = currentPanel.attributes[:height].slice!(/\D*$/)
          if unit == "x" then
            currentPanel.attributes[:height] = currentPanel.attributes[:height].to_f * @defaults[:panel_height]
          elsif unit == "max" then
            currentPanel.attributes[:height] = 0 # deal with this case later
          else
            currentPanel.attributes[:height] = currentPanel.attributes[:height].to_f
          end
        else
          currentPanel.attributes[:height] = @defaults[:panel_height]
        end
        # ---
        panel.search("text").each do |text|
          currentText = Hash.new
          currentText[:content] = text.inner_html.strip
          text.attributes.each do |key, value|
            currentText[key.to_sym] = value
          end
          currentPanel.text << currentText
        end
        currentPage.panels << currentPanel
      end
      @pages << currentPage.arrange!
    end
  end
  
  def generate(target)
    if target == :indesign then
      
      puts "generating indesign document..."
      
      indesign = app("Adobe InDesign CS3")
      indesign.view_preferences.ruler_origin.set(:page_origin)
      indesign.view_preferences.set(app.view_preferences.horizontal_measurement_units, :to => :millimeters)
      indesign.view_preferences.set(app.view_preferences.vertical_measurement_units, :to => :millimeters)
      indesign.margin_preferences.set(app.margin_preferences.top, :to => @defaults[:kopfsteg] )
      indesign.margin_preferences.set(app.margin_preferences.bottom, :to => @defaults[:fusssteg] )
      indesign.margin_preferences.set(app.margin_preferences.left, :to => @defaults[:bundsteg] )
      indesign.margin_preferences.set(app.margin_preferences.right, :to => @defaults[:aussensteg] )
      doc = indesign.make(:new => :document, :with_properties => {
          :document_preferences => {                                 
                                       :pages_per_document => pages.size,
                                       :facing_pages => true,
                                       :page_width => @defaults[:pagewidth],
                                       :page_height => @defaults[:pageheight],
                                   },                      
      })
      # make Layers
      layer = Hash.new
      [ "background", "panels", "overlay", "text boxes", "speech bubbles"].each do |layername|
        layer[layername.gsub(/\s/, "_").to_sym] = doc.make( :new => :layer, :with_properties => { :name => layername } )
      end
      # make Character-Styles
      char_style = Hash.new
      [ "box", "speech", "think" ].each do |charStyleName|
        char_style[charStyleName.to_sym] = doc.make( :new => :character_style, :with_properties => { :name => charStyleName } )
      end    
      # make Paragraph-Styles
      paragraph_style = Hash.new
      [ "box", "speech", "think" ].each do |paragraphStyleName|
        paragraph_style[paragraphStyleName.to_sym] = doc.make( :new => :paragraph_style, :with_properties => { :name => paragraphStyleName } )
        paragraph_style[paragraphStyleName.to_sym].justification.set :center_align
      end    
      paragraph_style[:box].justification.set :left_align
      
      div2 = @defaults[:dividerwidth] / 2
      dpmm = @defaults[:resolution] / 25.4
      
      pages.each do |p|
        p.panels.each do |panel|
          frame = doc.pages[p.attributes[:id]].make( :new => :rectangle, :with_properties => {   
            :item_layer => layer[:panels],            
            :geometric_bounds => [
              panel.origin.y + div2, 
              panel.origin.x + div2, 
              panel.origin.y + panel.size.y - div2, 
              panel.origin.x + panel.size.x - div2  ], 
            :stroke_color => "Black",
            :stroke_weight => 2
          })
          
          imgFolder = "images#{@defaults[:id]}"
          pageFolder = "#{imgFolder}/page#{p.attributes[:id]}"
          filename = "#{pageFolder}/panel#{p.attributes[:id]}_#{panel.attributes[:id]}.jpeg"
          
          if File::exists?( filename ) then
            frame.place( 
              MacTypes::Alias.path( filename ),
              :destination_layer => layer[:panels],
              :with_properties => { 
                :geometric_bounds => [
                  panel.origin.y + div2 - defaults[:imageborder]/dpmm, 
                  panel.origin.x + div2 - defaults[:imageborder]/dpmm, 
                  panel.origin.y + panel.size.y - div2 + defaults[:imageborder]/dpmm, 
                  panel.origin.x + panel.size.x - div2 + defaults[:imageborder]/dpmm  ],
              }
            )
          end
          
          if panel.attributes[:type].to_sym == :background then
            frame.item_layer.set layer[:background]
            frame.stroke_color.set "None"
          elsif panel.attributes[:type].to_sym == :overlay then
            frame.item_layer.set layer[:overlay]
          end
          
          panel.text.each do |text|
            
            if text[:type] == "box" then # TextBox "meanwhile..." Style
              
              textframe = doc.pages[p.attributes[:id]].make( 
                :new => :text_frame, 
                :with_properties => { 
                  :inset_spacing => [5,5,5,5],  
                  :item_layer => layer[:text_boxes],    
                  :contents => text[:content],
                  :geometric_bounds => [
                    panel.origin.y + @defaults[:dividerwidth], 
                    panel.origin.x + @defaults[:dividerwidth], 
                    panel.origin.y + panel.size.y - div2, 
                    panel.origin.x + panel.size.x - div2  ],                      
                  :stroke_color => "Black",
                  :fill_color => "Paper",
                  :stroke_weight => 2
                }
              )
              textframe.text_frame_preferences.inset_spacing.set [div2,div2,div2,div2]
              textframe.paragraphs.applied_paragraph_style.set paragraph_style[:box]
              textframe.fit :given => :frame_to_content
              
            else # ordinary speech bubble
              
              # load speechbubble data
              bubbledata = YAML.load_file File.expand_path( File.dirname(__FILE__) + "/bubbles.yaml" )
              bubbledata = bubbledata[ text[:type].to_sym ]
              
              # create a generic polygon
              bubble = doc.pages[p.attributes[:id]].make(
                :new => :polygon,
                :with_properties => {
                  :item_layer => layer[:speech_bubbles],    
                  :content_type => :text_type,
                  :fill_color => "Paper",
                  :number_of_sides => bubbledata.length,
                  :stroke_weight => 1
                }
              )
                           
              # draw speechbubble
              
              point_array = bubble.paths.first.path_points.get
              factor = 3
              
              point_array.each_index do |i|

                pnt = {
                  :anchor   => Point.new( bubbledata[i][:anchor] ),
                  :left     => Point.new( bubbledata[i][:left] ),
                  :right    => Point.new( bubbledata[i][:right] )
                }

                pnt.each do |key, value| pnt[key] = value * factor end

                unless pnt[:left].parallel?(pnt[:right]) then
                  point_array[i].point_type.set( :corner )
                end

                point_array[i].anchor.set( pnt[:anchor].to_array )
                point_array[i].left_direction.set( (pnt[:anchor] + pnt[:left]).to_array )
                point_array[i].right_direction.set( (pnt[:anchor] + pnt[:right]).to_array )
              end
              
              # enter text into speechbubble
              bubble.text_frame_preferences.inset_spacing.set [div2,div2,div2,div2]
              bubble.contents.set text[:content]
              bubble.paragraphs.applied_paragraph_style.set paragraph_style[:speech]
              bubble.fit :given => :frame_to_content
              bubble.move :to => [panel.origin.x, panel.origin.y + div2*2]
              
              # make Speechbubble invisible
              if text[:type].to_sym == :free then
                bubble.fill_color.set "None"
                bubble.stroke_color.set "None"
              end
              
            end
          end
          
        end
      end
      
    elsif target == :images then
      puts "generating images..."
      
      
      dpmm = defaults[:resolution] / 25.4 # "Dots per mm" – 300dpi / 25.4 (mm per inch)
      imgFolder = "images#{@defaults[:id]}"
      
      unless File::directory?( imgFolder ) then
        Dir.mkdir( imgFolder )
      end
      
      pages.each do |page|
        pageFolder = "#{imgFolder}/page#{page.attributes[:id]}"
        unless File::directory?( pageFolder ) then
          Dir.mkdir( pageFolder )
        end
               
        page.panels.each do |panel|
          filename = "#{pageFolder}/panel#{page.attributes[:id]}_#{panel.attributes[:id]}.jpeg"
          unless File::exists?( filename )
            
            border = defaults[:imageborder]
            px = panel.size.x * dpmm
            py = panel.size.y * dpmm
            
            img = Image.new( px + border*2, py + border*2 ) {
              self.background_color = 'white'
            }
          
            d = Draw.new
          
            d.fill("#888888")
            d.line(border, border*2, border, border)
            d.line(border, border, border*2, border)
            d.line(px, py+border, px+border, py+border)
            d.line(px+border, py+border, px+border, py)
            
            d.font_family('Georgia')
            d.font_weight(Magick::NormalWeight)
            d.pointsize(9)
            d.font_style(Magick::NormalStyle)
            d.gravity(Magick::SouthWestGravity)
          
            if panel.attributes[:description] then
              d.text( border, border-10, "#{panel.attributes[:description]}")
            end
            
            d.draw( img )

            img.write( filename )
          end
        end
      end 
      
    elsif target == :pdf then
      puts "target pdf: not yet implemented"
    end
    
  end
  
end
