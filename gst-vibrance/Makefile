PLUGIN = libgstvibrance.so
CFLAGS += -O2 -fPIC -Wall $(shell pkg-config --cflags gstreamer-video-1.0)
LIBS = $(shell pkg-config --libs gstreamer-video-1.0)
PLUGINDIR = /usr/local/lib/gstreamer-1.0

all: $(PLUGIN)

$(PLUGIN): gstvibrance.c
	$(CC) $(CFLAGS) -shared -o $@ $< $(LIBS)

install: $(PLUGIN)
	install -D -m 644 $(PLUGIN) $(PLUGINDIR)/$(PLUGIN)

clean:
	rm -f $(PLUGIN)
