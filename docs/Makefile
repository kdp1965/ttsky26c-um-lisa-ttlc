SRCS = $(wildcard *.txt)
PNGS = $(SRCS:.txt=.png)

ASCEE = ../../../../ascee/ascee

all: $(PNGS)

%.png: %.txt
	$(ASCEE) -f png $<

info:
	@echo $(PNGS)
