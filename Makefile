# conatus_code 二进制打包入口。常用：
#   make            # 编译产出 dist/nava（等价 make build）
#   make install    # 编译并软链 ~/bin/nava（已在 PATH）
#   make clean      # 删除 dist/
#   make test       # 跑包内测试

OUTPUT ?= dist/nava

.PHONY: all build install clean test

all: build

build:
	bash tool/build_binary.sh $(OUTPUT)

install: build
	ln -sf "$(CURDIR)/dist/nava" "$(HOME)/bin/nava"
	@echo "已链接：$(HOME)/bin/nava -> $(CURDIR)/dist/nava"

clean:
	rm -rf dist

test:
	dart test
