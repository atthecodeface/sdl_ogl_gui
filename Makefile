all: plot

.PHONY:plot
plot:
	jbuilder build src/plot_obj/plot_obj.exe
	DYLD_LIBRARY_PATH=~/Git/sdl_ogl_gui/_build/default/src/sdl_ogl_gui/sdl _build/default/src/plot_obj/plot_obj.exe

.PHONY:clean
clean:
	jbuilder clean

install:
	jbuilder build @install
	jbuilder install
