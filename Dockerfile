FROM efrecon/mini-tcl
MAINTAINER Emmanuel Frecon <efrecon@gmail.com>

# Copy files, arrange to copy the READMEs, which will also create the
# relevant directories.
COPY *.tcl /opt/weather/
COPY lib/modules /opt/weather/lib/modules
COPY lib/til /opt/weather/lib/til
COPY lib/toclbox /opt/weather/lib/toclbox

# Expose the default HTTP incoming port.
EXPOSE 8080

ENTRYPOINT ["tclsh8.6", "/opt/weather/weather.tcl"]