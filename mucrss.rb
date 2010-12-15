require 'rubygems'
require 'jabber/mucbot'
require 'mechanize'
require 'rss/2.0'
require 'rss/maker'

class MucRss
  # from URI.regexp
  UriRegxp = \
    /((?x-mi:(?:(?:(?=(?-mix:ftp|http|https):)
             ([a-zA-Z][-+.a-zA-Z\d]*):                           (?# 1: scheme)
             )|(?=(?:ww\w|ftp)(?:[.][a-zA-Z\d]+)+))
             (?:
              ((?:[-_.!~*'()a-zA-Z\d;?:@&=+$,]|%[a-fA-F\d]{2})(?:[-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]|%[a-fA-F\d]{2})*)                    (?# 2: opaque)
              |
              (?:(?:
                  \/\/(?:
                       (?:(?:((?:[-_.!~*'()a-zA-Z\d;:&=+$,]|%[a-fA-F\d]{2})*)@)?        (?# 3: userinfo)
                        (?:((?:(?:(?:[a-zA-Z\d](?:[-a-zA-Z\d]*[a-zA-Z\d])?)\.)*(?:[a-zA-Z](?:[-a-zA-Z\d]*[a-zA-Z\d])?)\.?|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\[(?:(?:[a-fA-F\d]{1,4}:)*(?:[a-fA-F\d]{1,4}|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})|(?:(?:[a-fA-F\d]{1,4}:)*[a-fA-F\d]{1,4})?::(?:(?:[a-fA-F\d]{1,4}:)*(?:[a-fA-F\d]{1,4}|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}))?)\]))(?::(\d*))?))? (?# 4: host, 5: port)
                        |
                        ((?:[-_.!~*'()a-zA-Z\d$,;:@&=+]|%[a-fA-F\d]{2})+)                 (?# 6: registry)
                      )
             |
               (?!\/\/))                           (?# XXX: '\/\/' is the mark for hostport)
               (\/(?:[-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*(?:;(?:[-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*)*(?:\/(?:[-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*(?:;(?:[-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*)*)*)?                    (?# 7: path)
              )(?:\?((?:[-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]|%[a-fA-F\d]{2})*))?                 (?# 8: query)
             )
             (?:\#((?:[-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]|%[a-fA-F\d]{2})*))?                  (?# 9: fragment)
     ))
             /x

  def initialize(config)
    @config = config
    @rsspath = @config[:rss]
    @rss = RSS::Parser.parse(@rsspath)
    raise RuntimeError, "Invalid rss at #@rsspath" if not @rss
    @rssmtx = Mutex.new

    @bot = Jabber::MUCBot.new(config)
    @bot.add_command(UriRegxp, &self.method(:handle_uri))
    @bot.add_command(/^#{@config[:nick]}\W+ur[il]/i, &self.method(:handle_question))
  end

  def handle_uri(sender, message)
    begin
      uris = message.scan(UriRegxp).map(&:first)
      uris = uris.map {|u| u = "http://#{u}" unless /^\w+:\/\// === u; u}.uniq
      uris.each do |u|
        Thread.new do
          # for debugging
          Thread.current.abort_on_exception = true
          a = Mechanize.new
          begin
            p = a.get(u)
            title = p.title
            desc = p.search('/html/head/meta[@name="description"]/@content').first
            desc = desc.content if desc
          rescue NoMethodError
          rescue Mechanize::ResponseCodeError
          end
          title ||= u
          desc ||= title

          @rssmtx.synchronize do
            it = @rss.channel.class::Item.new
            it.author = sender
            it.title = title
            it.link = u
            it.description = desc
            it.date = Time.now

            @rss.items << it
            @rss.items.sort!{|a,b| b.date <=> a.date}

            File.open(@rsspath, 'w') do |f|
              f.puts @rss
            end
          end

          #send("#{u} #{title} = #{desc}")
        end
      end
    rescue REXML::ParseException
    end
    nil
  end

  def handle_question(sender, message)
    @bot.send(@rss.channel.link)
  end

  def run
    @bot.join
    sleep
  end
end

if $0 == __FILE__
  require 'optparse'

  options = {}
  OptionParser.new do |opts|
    opts.banner = "usage: mucrss.rb [options]"

    opts.on("--rss RSS", "RSS file to read/write") do |v|
      options[:rss] = v.untaint
    end
    opts.on("--jid JID", "JID of the bot") do |v|
      options[:jid] = v
    end
    opts.on("--pass PASS", "password for the jid") do |v|
      options[:password] = v
    end
    opts.on("--nick NICK", "nick to use") do |v|
      options[:nick] = v
    end
    opts.on("--server SERVER", "conference server (without conference.)") do |v|
      options[:server] = v
    end
    opts.on("--room ROOM", "MUC room to join") do |v|
      options[:room] = v
    end
    opts.on("--[no-]debug", "enable debugging") do |v|
      options[:debug] = v
    end
  end.parse!

  [:rss, :jid, :password, :nick, :server, :room].each do |e|
    abort "need to specify #{e}" if not options[e]
  end

  options[:keep_alive] = false

  mr = MucRss.new(options)
  mr.run
end
