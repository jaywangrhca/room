# modify from Gserver.rb
require "socket"
require "thread"

class Roomserv
    DEFAULT_HOST = "127.0.0.1"

    def serve(io)  # interact with client thread
    end

    @@services = {}   # Hash of opened ports, i.e. services
    @@servicesMutex = Mutex.new

    # Stop the server running on the given port, bound to the given host
    #
    # +port+:: port, as a FixNum, of the server to stop
    # +host+:: host on which to find the server to stop
    def Roomserv.stop(port, host = DEFAULT_HOST)
        @@servicesMutex.synchronize {
            @@services[host][port].stop
        }
    end

    # Check if a server is running on the given port and host
    #
    # +port+:: port, as a FixNum, of the server to check
    # +host+:: host on which to find the server to check
    #
    # Returns true if a server is running on that port and host.
    def Roomserv.in_service?(port, host = DEFAULT_HOST)
        @@services.has_key?(host) and
            @@services[host].has_key?(port)
    end

    # Stop the server
    def stop
        @connectionsMutex.synchronize  {
            if @tcpServerThread
                @tcpServerThread.raise "stop"
            end
        }
    end

    # Returns true if the server has stopped.
    def stopped?
        @tcpServerThread == nil
    end

    # Schedule a shutdown for the server
    def shutdown
        @shutdown = true
    end

    # Return the current number of connected clients
    def connections
        @connections.size
    end

    def clients
        @clients
    end

    def set_ready(client)
        @clients[client][:ready] = true
    end

    def unset_ready(client)
        @clients[client][:ready] = nil
    end

    def set_name(client, name)
        @clients[client][:name] = name
    end

    # Join with the server thread
    def join
        @tcpServerThread.join if @tcpServerThread
    end

    # Port on which to listen, as a FixNum
    attr_reader :port
    # Host on which to bind, as a String
    attr_reader :host
    # Maximum number of connections to accept at at ime, as a FixNum
    attr_reader :maxConnections
    # IO Device on which log messages should be written
    attr_accessor :stdlog
    # Set to true to cause the callbacks #connecting, #disconnecting, #starting,
    # and #stopping to be called during the server's lifecycle
    attr_accessor :audit
    # Set to true to show more detailed logging
    attr_accessor :debug

    # Called when a client connects, if auditing is enabled.
    #
    # +client+:: a TCPSocket instances representing the client that connected
    #
    # Return true to allow this client to connect, false to prevent it.
    def connecting(client)
        addr = client.peeraddr
        log("#{self.class.to_s} #{@host}:#{@port} client:#{addr[1]} " +
            "#{addr[2]}<#{addr[3]}> connect")
        true
    end


    # Called when a client disconnects, if audition is enabled.
    #
    # +clientPort+:: the port of the client that is connecting
    def disconnecting(clientPort)
        log("#{self.class.to_s} #{@host}:#{@port} " +
            "client:#{clientPort} disconnect")
    end

    protected :connecting, :disconnecting

    # Called when the server is starting up, if auditing is enabled.
    def starting()
        log("#{self.class.to_s} #{@host}:#{@port} start")
    end

    # Called when the server is shutting down, if auditing is enabled.
    def stopping()
        log("#{self.class.to_s} #{@host}:#{@port} stop")
    end

    protected :starting, :stopping

    # Called if #debug is true whenever an unhandled exception is raised.
    # This implementation simply logs the backtrace.
    #
    # +detail+:: The Exception that was caught
    def error(detail)
        log(detail.backtrace.join("\n"))
    end

    # Log a message to #stdlog, if it's defined.  This implementation
    # outputs the timestamp and message to the log.
    #
    # +msg+:: the message to log
    def log(msg)
        if @stdlog
            @stdlog.puts("[#{Time.new.ctime}] %s" % msg)
            @stdlog.flush
        end
    end

    protected :error, :log

    # Create a new server
    #
    # +port+:: the port, as a FixNum, on which to listen.
    # +host+:: the host to bind to
    # +maxConnections+:: The maximum number of simultaneous connections to
    #                    accept
    # +stdlog+:: IO device on which to log messages
    # +audit+:: if true, lifecycle callbacks will be called.  See #audit
    # +debug+:: if true, error messages are logged.  See #debug
    def initialize(port, host = DEFAULT_HOST, maxConnections = 4,
                   stdlog = $stderr, audit = false, debug = false)
        @tcpServerThread = nil
        @port = port
        @host = host
        @maxConnections = maxConnections
        @connections = []
        @clients = {}
        @connectionsMutex = Mutex.new
        @connectionsCV = ConditionVariable.new
        @stdlog = stdlog
        @audit = audit
        @debug = debug
    end

    # Start the server if it isn't already running
    #
    # +maxConnections+::
    #   override +maxConnections+ given to the constructor.  A negative
    #   value indicates that the value from the constructor should be used.
    def start(maxConnections = -1)
        raise "server is already running" if !stopped?
        @shutdown = false
        @maxConnections = maxConnections if maxConnections > 0
        @@servicesMutex.synchronize  {
            if Roomserv.in_service?(@port,@host)
                raise "Port already in use: #{host}:#{@port}!"
            end
            @tcpServer = TCPServer.new(@host,@port)
            @port = @tcpServer.addr[1]
            @@services[@host] = {} unless @@services.has_key?(@host)
            @@services[@host][@port] = self;
        }
        @tcpServerThread = Thread.new {
            begin
                starting if @audit
                while !@shutdown
                    @connectionsMutex.synchronize  {
                        while @connections.size >= @maxConnections
                            @connectionsCV.wait(@connectionsMutex)
                        end
                    }
                    client = @tcpServer.accept
                    @connectionsMutex.synchronize  {
                        @clients[client] = { name:  nil,
                                             ready: nil,
                                             paddr: nil }
                    }
                    Thread.new(client)  { |myClient|
                        @connections << Thread.current
                        begin
                            myPort = myClient.peeraddr[1]
                            myHost = myClient.peeraddr[3]
                            paddr  = "#{myHost}:#{myPort}"
                            p paddr
                            @clients[myClient][:paddr] = paddr
                            serve(myClient) if !@audit or connecting(myClient)
                        rescue => detail
                            error(detail) if @debug
                        ensure
                            begin
                                myClient.close
                            rescue
                            end
                            @connectionsMutex.synchronize {
                                @connections.delete(Thread.current)
                                @connectionsCV.signal
                            }
                            disconnecting(myPort) if @audit
                        end
                    }
                end
            rescue => detail
                error(detail) if @debug
            ensure
                begin
                    @tcpServer.close
                rescue
                end
                if @shutdown
                    @connectionsMutex.synchronize  {
                        while @connections.size > 0
                            @connectionsCV.wait(@connectionsMutex)
                        end
                    }
                else
                    @connections.each { |c| c.raise "stop" }
                end
                @tcpServerThread = nil
                @@servicesMutex.synchronize  {
                    @@services[@host].delete(@port)
                }
                stopping if @audit
            end
        }
        self
    end

end
