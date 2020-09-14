
/*

Cocktail Mode
	
Allows you to mirror and flip your game to use for arcade cocktail cabinets
on a single display. 

To apply the border:

1. Have an image you want as the border located in the texture folder 
or wherever you set reshade to for textures. PNG or JPG works.

2. rename the image to "Border.png" or edit the preprocessor definitions to 
the name of the image file

3. Edit the preprocessor definitions "BORDER_SIZE_X" and "BORDER_SIZE_Y" to 
the dimensions of the image.

4. Press the reload button.
	
Copyright (c) 2020 James Nguyen
	
This work is licensed under the Creative Commons 
Attribution-NonCommercial-ShareAlike 4.0 International License.
To view a copy of this license, visit 
http://creativecommons.org/licenses/by-nc-sa/4.0/

Credits to Jacob Max Fober for the steroscopic and scale code I used
from his VR Shader you can find here:
https://reshade.me/forum/shader-presentation/5104-vr-universal-shader.

*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/* Border Image Definitions */
#ifndef BORDER_SOURCE
#define BORDER_SOURCE "Border.png"
#endif

#ifndef BORDER_SIZE_X
#define BORDER_SIZE_X 1280
#endif

#ifndef BORDER_SIZE_Y
#define BORDER_SIZE_Y 720
#endif

#if BORDER_SINGLECHANNEL
    #define TEXFORMAT R8
#else
    #define TEXFORMAT RGBA8
#endif

/* Static Values */
static const float PI = 3.14159265f;

/* Menu Options */
uniform float MT < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Mirror Type";
	ui_tooltip = "Select how to mirror the image";
	ui_category = "Mirror Settings";
	ui_min = 1; ui_max = 4;
	ui_step = 1;
> = 3;

uniform float MD <  __UNIFORM_SLIDER_FLOAT1
	ui_label = "Mirror Distance";
	ui_tooltip = "Adjust the distance between the mirror";
	ui_category = "Mirror Settings";
	ui_min = 0; ui_max = 0.75; ui_step = 0.001;
	ui_category_closed = true;
> = 0.5;

uniform float ImageScale < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Image scale";
	ui_tooltip = "Adjust image size";
	ui_category = "Mirror Settings";
	ui_min = 0.25; ui_max = 1.0;
> = 0.317;

uniform bool Portrait <
	ui_label = "Portrait Mode";
	ui_category = "Mirror Settings";
> = true;

uniform float2 Border_Pos < __UNIFORM_DRAG_FLOAT2
    ui_label = "Border Position";
	ui_category = "Border Settings";
    ui_min = -10; ui_max = 10.0;
    ui_step = (1.0 / 200.0);
> = float2(0.5, 0.5);

uniform float Border_Scale < __UNIFORM_DRAG_FLOAT1
    ui_label = "Border Scale";
	ui_category = "Border Settings";
    ui_min = (1.0 / 100.0); ui_max = 4.0;
    ui_step = (1.0 / 250.0);
> = 2.0;
uniform bool Border_Style <
	ui_label = "Alternate Border Style";
	ui_category = "Border Settings";
> = false;

/* Textures */
texture Border_Tex <
    source = BORDER_SOURCE;
> {
    Format = TEXFORMAT;
    Width  = BORDER_SIZE_X;
    Height = BORDER_SIZE_Y;
};

/* Samplers */
sampler Border_Sampler
{
    Texture  = Border_Tex;
    AddressU = BORDER;
    AddressV = BORDER;
};

/* Functions */

// Divide screen into two halfs
float2 StereoVision(float2 Coordinates, float Center)
{
	float2 StereoCoord = Coordinates;
	
	// Mirror left half
	float ScreenSide;
	if(MT== 1) {
	StereoCoord.x = 0.25 + abs( StereoCoord.x*2.0-1.0 ) * 0.5; // Divide screen in two
	StereoCoord.x -= lerp(-0.25, 0.25, Center); // Change center for interpupillary distance (IPD)
	ScreenSide = step(0.5, Coordinates.x);
	StereoCoord.x *= ScreenSide*2.0-1.0;
	StereoCoord.x += 1.0 - ScreenSide;
	}
	
	if(MT == 2) {
	StereoCoord.y = 0.25 + abs( StereoCoord.y*2.0-1.0 ) * 0.5; // Divide screen in two
	StereoCoord.y -= lerp(-0.25, 0.25, Center); // Change center for interpupillary distance (IPD)
	ScreenSide = step(0.5, Coordinates.y);
	StereoCoord.y *= ScreenSide*2.0-1.0;
	StereoCoord.y += 1.0 - ScreenSide;
	}
	
	if(MT == 3) {
	StereoCoord.x = 0.25 + abs( StereoCoord.x*2.0-1.0 ) * 0.5; // Divide screen in two
	StereoCoord.x -= lerp(-0.25, 0.25, Center); // Change center for interpupillary distance (IPD)
	ScreenSide = step(0.5, Coordinates.x);
	StereoCoord.y *= ScreenSide*2.0-1.0;
	StereoCoord.y += 1.0 - ScreenSide;
	}
	
	if(MT == 4) {
	StereoCoord.y = 0.25 + abs( StereoCoord.y*2.0-1.0 ) * 0.5; // Divide screen in two
	StereoCoord.y -= lerp(-0.25, 0.25, Center); // Change center for interpupillary distance (IPD)
	ScreenSide = step(0.5, Coordinates.y);
	StereoCoord.x *= ScreenSide*2.0-1.0;
	StereoCoord.x += 1.0 - ScreenSide;
	}
	
	return StereoCoord;
};

// Generate border mask with anti-aliasing from UV coordinates
float BorderMaskAA(float2 Coordinates)
{
	float2 RaidalCoord = abs(Coordinates*2.0-1.0);
	// Get pixel size in transformed coordinates (for anti-aliasing)
	float2 PixelSize = fwidth(RaidalCoord);

	// Create borders mask (with anti-aliasing)
	float2 Borders = smoothstep(1.0-PixelSize, 1.0+PixelSize, RaidalCoord);

	// Combine side and top borders
	return max(Borders.x, Borders.y);
};

// Rotate Image
float2 rotateUV(float2 uv, float rotation)
{
	float pivot = 0.5;
    return float2(
        cos(rotation) * (uv.x - pivot) + sin(rotation) * (uv.y - pivot) + pivot,
        cos(rotation) * (uv.y - pivot) - sin(rotation) * (uv.x - pivot) + pivot
    );
}

float3 Cocktail_ps(float4 vois : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	// Get display aspect ratio (horizontal/vertical resolution)
	static const float rAspect = ReShade::AspectRatio;

	// Divide screen in two
	float2 UvCoord = StereoVision(texcoord, MD);
	
	// Set up values for the border image
	const float2 pixelSize = 1.0 / (float2(BORDER_SIZE_X, BORDER_SIZE_Y) * Border_Scale / BUFFER_SCREEN_SIZE);
	
	float4 border = tex2D(Border_Sampler, texcoord * pixelSize + Border_Pos * (1.0 - pixelSize));
	
	// Rotate the screen 
	if (Portrait) {
		UvCoord = rotateUV(UvCoord, 3*PI/2);	
	} 
	
	// Center coordinates
	UvCoord = UvCoord*2.0-1.0;
	
	// Maintain aspect ration based on screen orientation
	if(Portrait) {
		UvCoord.x /= rAspect;
	} else {
		UvCoord.x *= rAspect;
	}
	
	// Scale image
	UvCoord /= ImageScale;
	
	// Revert aspect ratio to square
	UvCoord.x /= rAspect;
	
	// Move origin back to left top corner
	UvCoord = UvCoord*0.5 + 0.5;
	
	if (Border_Style) {
		border = tex2D(Border_Sampler, UvCoord * pixelSize + Border_Pos * (1.0 - pixelSize));
	} 
	
	// Sample image with custom border to display
	float3 Image = lerp(
		tex2D(ReShade::BackBuffer, UvCoord).rgb, // Display image
		border, // border
		BorderMaskAA(UvCoord) // Anti-aliased border mask
	);

	// Display image
	return Image;
};

technique Cocktail < ui_label = "Cocktail Mode"; ui_tooltip = "Cocktail Mode:\n" ;>
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = Cocktail_ps;
	}
};
