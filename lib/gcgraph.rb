require 'webrick'
require 'erb'

module GCGraph
  class GraphGen
    def initialize(xsize, ysize, xscale = 1)
      @xsize = xsize
      @ysize = ysize
      @xscale = xscale
    end

    def xscale=(sc)
      @xscale = sc
      set_data_range(@ominx, @maxx, @miny, @maxy)
    end
    
    def set_data_range(minx, maxx, miny, maxy)
      @ominx = minx.to_f
      @maxx = maxx.to_f
      @miny = miny.to_f
      @maxy = maxy.to_f

      if @ominx + @xscale < @maxx then
        @minx = @maxx - @xscale
      else
        @minx = @ominx
      end
    end
    
    def position_in_graph(x, y)
      if x < @minx or @maxx < x then
        return [nil, nil]
      end
      if y < @miny or @maxy < y then
        return [nil, nil]
      end

      dx = @maxx - @minx
      posx = ((x - @minx) / dx) * @xsize
      
      dy = @maxy - @miny
      posy = ((y - @miny) / dy) * @ysize
      
      [posx, posy]
    end
  end
  
  class GraphGenCanvas<GraphGen
    NUM_VLABEL = 10
    NUM_HLABEL = 5
    
    BODRER_SCRIPT_TEMPLATE = <<EOS
    function draw_border() {
      var canctx = document.getElementById('border').getContext('2d')
      canctx.rect(0, 0, <%= @xsize%>, <%= @ysize%>);
      canctx.stroke();

      canctx.strokeStyle = 'rgb(0, 128, 128)';
      canctx.lineWidth = 0.5;

      var cnt = 0;
      while (cnt < <%= @ysize%>){
        cnt += 40;
        canctx.beginPath();
        canctx.moveTo(0,  cnt);
        canctx.lineTo(<%= @xsize%>,  cnt);
        canctx.stroke();
      }

      cnt = 0;
      while (cnt < <%= @xsize%>){
        cnt += 40;
        canctx.beginPath();
        canctx.moveTo(cnt, 0);
        canctx.lineTo(cnt, <%= @ysize%>);
        canctx.stroke();
      }
    }
EOS

    def graph_script_begin
<<EOS
    var canctx = document.getElementById('graph').getContext('2d');
EOS
    end

    def graph_script_set_line_prop(color)
<<EOS
    canctx.strokeStyle = '#{color}';
    canctx.lineWidth = 3;
EOS
    end

    def initialize(xsize, ysize)
      super
    end

    def set_data(data)
      xmin = nil
      xmax = nil
      ymin = nil
      ymax = nil
      @data = []
      data.each do |gd|
        sd = gd.sort_by {|a| a[0]}
        sdx = sd.map {|a| a[0]}
        sdy = sd.map {|a| a[1]}
        cymin = sdy.min
        if ymin == nil or cymin < ymin then
          ymin = cymin
        end
        if ymin > 0 then
          ymin = 0
        end

        cymax = 10 ** ((Math.log10(sdy.max + 1.1)).to_i + 1)
        if ymax == nil or ymax < cymax then
          ymax = cymax
        end

        cxmin = sdx.min
        if xmin == nil or cxmin < xmin then
          xmin = cxmin
        end

        cxmax = sdx.max
        if xmax == nil or xmax < cxmax then
          xmax = cxmax
        end

        @data.push sd
      end

      set_data_range(xmin, xmax, ymin, ymax)
    end

    def border_script
      ERB.new(BODRER_SCRIPT_TEMPLATE).result(binding)
    end

    GraphColor = ['Red', 'Blue']
    def graph_script
      res = "canctx.clearRect(0, 0, #{@xsize}, #{@ysize});\n" 
      @data.each_with_index do |gd, i|
        agraph = ""
        gd.each do |a|
          x, y = position_in_graph(a[0], a[1])
          if x then
            y = @ysize - y
            agraph += "canctx.moveTo(#{x}, #{@ysize});\n"
            agraph += "canctx.lineTo(#{x}, #{y});\n"
          end
        end

        res += graph_script_set_line_prop(GraphColor[i])
        res += "canctx.beginPath();\n"
        res += agraph
        res += "canctx.stroke();"
      end
      graph_script_begin + res
    end

    def vlabel_css
      res = ""
      iy = @ysize + 40
      dy = @ysize / NUM_VLABEL
      (0..NUM_VLABEL).each do |i|
        value = "left: 0px; top: #{iy  -  dy * i}px"
        res += "span#vlabel#{i} { #{value} }\n"
      end
      
      res
    end

    def vlabel_html
      res = ""
      iy = @miny
      dy = (@maxy - @miny) / NUM_VLABEL
      (0..NUM_VLABEL).each do |i|
        res += "<span id=\"vlabel#{i}\"> #{iy  +  dy * i} </span>\n"
      end
      
      res
    end

    def vlabel_script
      res = ""
      iy = @miny
      dy = (@maxy - @miny) / NUM_VLABEL
      (0..NUM_VLABEL).each do |i|
        dest = "document.getElementById(\"vlabel#{i}\").innerHTML"
        res += "#{dest} = #{iy  +  dy * i};\n"
      end
      
      res
    end

    def hlabel_css
      res = ""
      ix = 40
      dx = @xsize / NUM_HLABEL
      (0..NUM_HLABEL).each do |i|
        value = "left: #{dx * i + ix}px; top: #{@ysize + 50}px"
        res += "span#hlabel#{i} { #{value} }\n"
      end
      
      res
    end

    def hlabel_html
      res = ""
      dx = (@maxx - @minx) / NUM_HLABEL
      (0..NUM_HLABEL).each do |i|
        res += "<span id=\"hlabel#{i}\"> #{dx * i + @minx} </span>\n"
      end
      
      res
    end

    def hlabel_script
      res = ""
      dx = (@maxx - @minx) / NUM_HLABEL
      (0..NUM_HLABEL).each do |i|
        dest = "document.getElementById(\"hlabel#{i}\").innerHTML"
        res += "#{dest} =  #{dx * i + @minx};\n"
      end
      
      res
    end
  end

  class GraphServer
    include WEBrick
    class GraphServlet<HTTPServlet::AbstractServlet
      SCRIPT = <<EOS
<html>
  <style type="text/css">
    canvas {position: absolute}
    span {position: absolute}
    canvas#border { left: 40px; top: 50px }
    canvas#graph { left: 40px; top: 50px }
    div#vlabel span {text-align: right; width: 30px }
    div#hlabel span {text-align: left; width: 30px }
    <%= @graph_gen.vlabel_css %>
    <%= @graph_gen.hlabel_css %>
  </style>
    
  <script type="text/javascript" id="gscript">
   <%= @graph_gen.border_script %>
  </script>

  <script type="text/javascript" id="main">
    function setscale(scale) {
      var xmlhttp = new XMLHttpRequest();
      xmlhttp.open("GET", "setscale?SCALE=" + scale, true);
      xmlhttp.send(null);
    }

    window.onload = function() {
      draw_border();
      var xmlhttp = new XMLHttpRequest();
      xmlhttp.open("GET", "update.js", true);
      xmlhttp.onreadystatechange=function() {
         if (xmlhttp.readyState == 4) {
           eval(xmlhttp.responseText);
         }
      }
      xmlhttp.send(null);
    };

  </script>
  <body>
    <canvas id="border" width="600px" height="400px"></canvas>
    <canvas id="graph" width="600px" height="400px"></canvas>
    <div id="vlabel">
      <%= @graph_gen.vlabel_html %>
    </div>
    <div id="hlabel">
      <%= @graph_gen.hlabel_html %>
    </div>
    Time Scale: 
    <input type="radio" name="sc" onClick="setscale(this.value);" value="1"/> 1
    <input type="radio" name="sc" onClick="setscale(this.value);" value="10"/> 10
    <input type="radio" name="sc" onClick="setscale(this.value);" value="100"/> 100
  </body>
</html>
EOS

      def do_GET(req, res)
        if !defined? @graph_gen then
          @graph_gen = GraphGenCanvas.new(600, 400)
        end
        
        @graph_gen.set_data([[[0, 0], [1, 1000]]])
        res.body = ERB.new(SCRIPT).result(binding)
        res['Content-Type'] = "text/html"
      end
    end

    class GraphServlet2<HTTPServlet::AbstractServlet
      ENDSCRIPT = <<EOS
    xmlhttp.open("GET", "update.js", true);
    xmlhttp.onreadystatechange=function() {
       if (xmlhttp.readyState == 4) {
            eval(xmlhttp.responseText);
       }
    }
    xmlhttp.send(null);
EOS

      def initialize(sv, opt)
        super
        @graph_gen = opt
      end

      def do_GET(req, res)
        sleep(1)
        @graph_gen.set_data(ObjectCounter.gdata)
        script = @graph_gen.graph_script
        script += @graph_gen.vlabel_script
        script += @graph_gen.hlabel_script
        res.body = script + ENDSCRIPT
        res['Content-Type'] = "text/javascript"
      end
    end

    class GraphServletSetScale<HTTPServlet::AbstractServlet
      def initialize(sv, opt)
        super
        @graph_gen = opt
      end

      def do_GET(req, res)
        scale = req.query['SCALE'].to_i
        if scale != 0 then
          @graph_gen.xscale = scale
        end
      end
    end

    def initialize
      @graph_gen = GraphGenCanvas.new(600, 400)
      @server = HTTPServer.new(:Port => 8088, :BindAddress => "localhost")
      @server.logger.close
      trap("INT"){@server.shutdown}
      @server.mount("/graph", GraphServlet)
      @server.mount("/update.js", GraphServlet2, @graph_gen)
      @server.mount("/setscale", GraphServletSetScale, @graph_gen)
      @server.start
    end
  end

  class ObjectCounter
    def self.gdata
      duse = []
      dtotal = []
      rep = GC::Profiler.result
      rep = rep.split(/\n/)
      rep.shift
      rep.shift
      
      if rep.size < 2 then
        rep = ["0 0 0 0 0", "0, 0.1, 1, 1, 1"] + rep
      end
      rep.each do |es|
        ea = es.split(/\s+/)
        duse.push [ea[2].to_f, ea[3].to_f]
        dtotal.push [ea[2].to_f, ea[4].to_f]
      end
      [dtotal, duse]
    end
  end
end  # GCGraph

GC::Profiler.enable
GC.start
Thread.new {
  a = GCGraph::GraphServer.new
}.run
