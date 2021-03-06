YAWS_INCLUDE=/usr/local/lib/yaws/include # Replace with the location of yaws_api.hrl

BEAM_DIR=ebin
SRC_DIR=src

all: $(SRC_DIR)/*.erl
	@[ -d ebin ] || mkdir -p ebin
	erlc -v -I$(YAWS_INCLUDE) -o $(BEAM_DIR) $(SRC_DIR)/*.erl

clean:
	(cd ebin; rm -f *.beam)





