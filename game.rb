require './roomserv'
class Gameroom < Roomserv
    def initialize *args
        super
    end

    def serve(player)
        welcome(player)
        broadcast("Welcome #{name}", self.clients)
        ready(player)
        p self.clients
    end

    def welcome(player)
        player.print 'Welcome! Please enter your name: '
        name = player.readline.chomp
        set_name(player, name)
    end

    def broadcast(message, clients)
        clients.each_key do |client|
            client.puts "Broadcast: #{message}"
        end
    end

    def ready(player)
        player.print 'Are you ready?(Yy/Nn)'
        if player.readline.chomp =~ /y/i
            # TODO
            puts "#{player} is ready!"
            set_ready(player)
        else
            puts "#{player} is not ready!"
            unset_ready(player)
        end
    end

    # players: thread => {name, ready, peeraddr}
    def players *args
        # TODO
    end
end

log = File.open('./sanguo.log', 'w') or raise 'Can not write to log file!'
sanguo = Gameroom.new(10002, 'localhost', 2, log)
sanguo.audit = true
sanguo.debug = true
sanguo.start
sleep 60
