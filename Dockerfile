FROM efrecon/mini-tcl
MAINTAINER Emmanuel Frecon <efrecon@gmail.com>

# Copy files, arrange to copy the READMEs, which will also create the
# relevant directories.
COPY *.tcl /opt/weather/
COPY lib/modules/*.tm /opt/weather/lib/modules/
COPY exts/*.tcl /opt/weather/exts/

# Install git so we can install dependencies, then weather into /opt and til in
# the lib subdirectory. Finally cleanup. Do this in one single go to keep the
# size of the image small.
RUN apk add --no-cache git && \
    git clone --depth 1 https://github.com/efrecon/til /opt/weather/lib/til && \
    rm -rf /opt/weather/lib/til/.git && \
    git clone --depth 1 https://github.com/efrecon/toclbox /opt/weather/lib/toclbox && \
    rm -rf /opt/weather/lib/toclbox/.git && \
    apk del git

# Expose the default HTTP incoming port.
EXPOSE 8080

# Export the plugin directory so it gets easy to test new plugins.
VOLUME /opt/weather/exts

ENTRYPOINT ["tclsh8.6", "/opt/weather/weather.tcl"]