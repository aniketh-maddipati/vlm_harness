# Lumina: the parity harness (Tools/parity/README.md). Everything else stays in Scripts/ and Tests/.
#
#   make render            build lumina-render (release)
#   make parity            Lightroom references vs Lumina renders → report (needs the Mac)
#   make parity STAGE=tone | SLIDER=Highlights | LIMIT=5 | RULES=path | LABEL=name | KINDS=base,single | DECODER=9
#   make parity-combos     the three-slider combinations only
#   make parity-check      Metal ≡ Swift ≡ numpy on flat patches (lumina-render ramp + lookmath.py --check)
#   make parity-test       the Python tests (Linux too)
#   make parity-loop       Tools/parity/loop.sh (every unlocked stage)
#
# The culling eval (Tools/culleval/README.md):
#   make culleval          grouping + auto keeps vs what was shot and kept → ~/LuminaEvidence/culleval/report
#   make culleval-test     its scoring tests (Linux too)

PARITY   := Tools/parity
RENDER   := $(PARITY)/lumina-render/.build/release/lumina-render
PY       ?= python3
REFS     ?= ~/LuminaEvidence/parity/refs.json
EVIDENCE ?= ~/LuminaEvidence/parity
STAGE    ?=
SLIDER   ?=
LIMIT    ?=
RULES    ?=
LABEL    ?=
DECODER  ?=
KINDS    ?= base,single,combo
PX       ?= 2048

PARITY_ARGS := --refs $(REFS) --render-dir $(EVIDENCE)/render --evidence $(EVIDENCE)/report --render-bin $(RENDER) --px $(PX) --kinds $(KINDS)
ifneq ($(STAGE),)
PARITY_ARGS += --stage $(STAGE)
endif
ifneq ($(SLIDER),)
PARITY_ARGS += --slider $(SLIDER)
endif
ifneq ($(LIMIT),)
PARITY_ARGS += --limit $(LIMIT)
endif
ifneq ($(RULES),)
PARITY_ARGS += --rules $(RULES)
endif
ifneq ($(LABEL),)
PARITY_ARGS += --label $(LABEL)
endif
ifneq ($(DECODER),)
PARITY_ARGS += --decoder $(DECODER)
endif

.PHONY: render parity parity-combos parity-check parity-personal parity-test parity-loop

render:
	swift build -c release --package-path $(PARITY)/lumina-render

parity: render
	$(PY) $(PARITY)/parity.py $(PARITY_ARGS)

parity-combos: render
	$(PY) $(PARITY)/parity.py $(PARITY_ARGS) --kinds combo --label combos

parity-check: render
	$(RENDER) ramp --out $(EVIDENCE)/render/ramp.json $(if $(RULES),--rules $(RULES),)
	$(PY) $(PARITY)/lookmath.py --check $(EVIDENCE)/render/ramp.json

# Lumina vs your own Lightroom exports (JPEGs with "All metadata" + their RAWs). Measures only.
#   make parity-personal EXPORTS=~/edits RAWS=~/raws [SET=~/LuminaEvidence/parity-personal] [ABLATE=1]
parity-personal:
	swift build -c release --package-path $(PARITY)/lumina-render
	$(PY) $(PARITY)/parity_personal.py $(if $(SET),--root $(SET)) $(if $(EXPORTS),--exports $(EXPORTS)) $(if $(RAWS),--raws $(RAWS)) $(if $(ABLATE),--ablate)

parity-test:
	$(PY) $(PARITY)/delta_e.py --selftest
	$(PY) -m unittest discover -s $(PARITY)/tests

parity-loop: render
	bash $(PARITY)/loop.sh $(STAGE)

.PHONY: culleval culleval-test

culleval:
	node Tools/culleval/culleval.mjs $(if $(CONFIG),--config $(CONFIG))

culleval-test:
	node --test Tools/culleval/tests/culleval.test.mjs
