#ifndef DEMO_H
#define DEMO_H

#include <string.h>
#include <stdio.h>

#include <SDL2/SDL.h>

#include <microui.h>


#include "renderer.h"

void test_window(mu_Context *ctx, float bg[3]);
void style_window(mu_Context *ctx);
void log_window(mu_Context *ctx);

#endif
