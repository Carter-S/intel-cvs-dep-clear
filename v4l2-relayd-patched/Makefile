# Patched v4l2-relayd (upstream 0.2.0, GPL-2.0, Canonical Ltd) with:
#  - grace period before camera teardown (Chrome flaps the reader count;
#    instant teardown = ~2.5s cold restart per flap = "blinking" camera)
#  - bounded leaky appsrc queue (was unbounded: ballooned to 100s of MB
#    under consumer backpressure, then SIGABRT)
BIN = v4l2-relayd
PKGS = gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 glib-2.0
CFLAGS += -O2 -Wall -DV4L2_RELAYD_VERSION='"0.2.0-patched"' -DG_LOG_DOMAIN='"v4l2-relayd"' $(shell pkg-config --cflags $(PKGS))
LIBS = $(shell pkg-config --libs $(PKGS))

all: $(BIN)

$(BIN): v4l2-relayd.c
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

install: $(BIN)
	install -D -m 755 $(BIN) /usr/local/bin/$(BIN)

clean:
	rm -f $(BIN)
