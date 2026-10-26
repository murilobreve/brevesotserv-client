/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#pragma once
#include "framework/core/timer.h"
#include "framework/graphics/declarations.h"
#include "framework/luaengine/luaobject.h"
#include "staticdata.h"

class AttachedEffect final : public LuaObject
{
public:
    static AttachedEffectPtr create(uint16_t thingId, ThingCategory category);

    void draw(const Point& /*dest*/, bool /*isOnTop*/, LightView* = nullptr, bool drawThing = true);
    void drawLight(const Point& /*dest*/, LightView*);

    uint16_t getId() { return m_id; }

    AttachedEffectPtr clone();

    float getSpeed() { return m_speed / 100.f; }
    void setSpeed(const float speed) { m_speed = speed * 100u; }

    float getOpacity() { return m_opacity / 100.f; }
    void setOpacity(const float opacity) { m_opacity = opacity * 100u; }

    Size getSize() { return m_size; }
    void setSize(const Size& s) { m_size = s; }

    bool isHidedOwner() { return m_hideOwner; }
    void setHideOwner(const bool v) { m_hideOwner = v; }

    bool isTransform() { return m_transform; }
    void setTransform(const bool v) { m_transform = v; }

    bool isDisabledWalkAnimation() { return m_disableWalkAnimation; }
    void setDisableWalkAnimation(const bool v) { m_disableWalkAnimation = v; }

    bool isPermanent() { return m_permanent; }
    void setPermanent(const bool permanent) { m_permanent = permanent; }

    bool isFollowingOwner() { return m_followOwner; }
    void setFollowOwner(const bool v) { m_followOwner = v; }

    uint16_t getDuration() { return m_duration; }
    void setDuration(const uint16_t v) { m_duration = v; }

    int8_t getLoop() { return m_loop; }
    void setLoop(const int8_t v) { m_loop = v; }

    void setName(std::string_view n) { m_name = n.data(); }
    std::string getName() { return m_name; }

    Otc::Direction getDirection() { return m_direction; }
    void setDirection(const Otc::Direction dir) { m_direction = std::min<Otc::Direction>(dir, Otc::NorthWest); }

    void setBounce(const uint8_t minHeight, const uint8_t height, const uint16_t speed) {
        m_bounce = { .minHeight = minHeight,.height = height, .speed = speed };
    }
    void setPulse(const uint8_t minHeight, const uint8_t height, const uint16_t speed) {
        m_pulse = { .minHeight = minHeight,.height = height, .speed = speed };
    }
    void setFade(const uint8_t start, const uint8_t end, const uint16_t speed) {
        m_fade = { .minHeight = start, .height = end,.speed = speed };
    }

    void setOnTop(const bool onTop) { for (auto& control : m_offsetDirections) control.onTop = onTop; }
    void setOffset(int16_t x, int16_t y) { for (auto& control : m_offsetDirections) control.offset = { x, y }; }
    void setOnTopByDir(const Otc::Direction direction, const bool onTop) { m_offsetDirections[direction].onTop = onTop; }

    void setDirOffset(const Otc::Direction direction, int8_t x, int8_t y, const bool onTop = false) {
        m_offsetDirections[direction] = { .onTop = onTop,.offset = {x, y} };
    }
    void setShader(std::string_view name);
    void setCanDrawOnUI(const bool canDraw) { m_canDrawOnUI = canDraw; }
    bool canDrawOnUI() { return m_canDrawOnUI; }

    void move(const Position& fromPosition, const Position& toPosition);

    void attachEffect(const AttachedEffectPtr& e) { m_effects.emplace_back(e); }

    DrawOrder getDrawOrder() { return m_drawOrder; }
    void setDrawOrder(const DrawOrder drawOrder) { m_drawOrder = drawOrder; }
    const Light& getLight() const { return m_light; }
    void setLight(const Light& light) { m_light = light; }

    ThingType* getThingType() const;

    // Layers (the skillshots' art v2): an image that the curves scale, fade,
    // move and turn, read in draw() so it stays smooth at any frame rate
    // with no Lua per frame. Curve keys are (t ms since attached, value,
    // ease) triples; before a layer's first key it is not drawn, after its
    // last the values hold.
    enum CurveChannel : uint8_t
    {
        CURVE_SCALE,    // 1 = the size set
        CURVE_STRETCH,  // more scale along x (a trail stretched along its way)
        CURVE_OPACITY,  // 0 to 1, times the opacity set
        CURVE_X,        // pixels (1x) right of the anchor's place
        CURVE_Y,        // pixels (1x) down
        CURVE_ROTATION, // degrees clockwise, added to setRotation's
        CURVE_LIGHT,    // the light's intensity (setLight gives the color)
        CURVE_COUNT
    };
    enum CurveEase : uint8_t
    {
        EASE_LINEAR,
        EASE_IN,         // speeds up into the key
        EASE_OUT,        // slows down into it
        EASE_IN_OUT,
        EASE_OUT_STRONG, // shoots off and brakes hard
        EASE_OVERSHOOT   // goes past the key and comes back
    };
    enum FramePlay : uint8_t
    {
        FRAMES_OWN,   // the image's own frame times
        FRAMES_ONCE,  // all its frames once in the time given, the last held
        FRAMES_LOOP,  // all its frames in the time given, again and again
        FRAMES_CLOCK  // a warning clock: the last frame only when the time is up
    };

    void setCurve(uint8_t channel, const std::vector<float>& keys);
    void setAnchor(const Point& anchor) { m_anchor = anchor; m_layered = true; }
    void setAdditive(const bool additive) { m_additive = additive; m_layered = true; }
    void setRotation(const float degrees) { m_rotation = degrees; m_layered = true; }
    // drawn upside down: turned by 180 degrees more, a layer facing right
    // faces left the right way up (a dragon kicked west)
    void setFlipped(const bool flipped) { m_flipped = flipped; m_layered = true; }
    // a particle: pixels (1x) per second right and down, pixels per second
    // squared down, degrees per second, from when the layer comes in
    void setMotion(const float vx, const float vy, const float gravity, const float spin) {
        m_motion = { .vx = vx, .vy = vy, .gravity = gravity, .spin = spin, .active = true };
        m_layered = true;
    }
    void setFramePlay(const uint8_t mode, const uint16_t durationMs) {
        m_framePlay = std::min<uint8_t>(mode, FRAMES_CLOCK);
        m_framePlayMs = durationMs;
        m_layered = true;
    }

private:
    int getCurrentAnimationPhase();
    void drawLayer(const Point& dest, LightView* lightView, bool drawThing);
    float curveValue(uint8_t channel, float t, float fallback) const;
    TexturePtr layerTexture(float t);

    struct DirControl
    {
        bool onTop{ false };
        Point offset;
    };

    int8_t m_loop{ -1 };

    uint8_t m_speed{ 100 };
    uint8_t m_opacity{ 100 };
    uint8_t m_lastAnimation{ 0 };
    DrawOrder m_drawOrder{ THIRD };

    uint16_t m_id{ 0 };
    uint16_t m_duration{ 0 };

    uint32_t m_frame{ 0 };

    bool m_hideOwner{ false };
    bool m_transform{ false };
    bool m_canDrawOnUI{ true };
    bool m_disableWalkAnimation{ false };
    bool m_permanent{ false };
    bool m_smooth = { true };
    bool m_followOwner{ false };

    Outfit m_outfitOwner;
    Light m_light;

    uint16_t m_thingId{ 0 };
    ThingCategory m_thingCategory{ ThingInvalidCategory };

    Size m_size;

    Timer m_animationTimer;

    Otc::Direction m_direction{ Otc::North };

    std::array<DirControl, Otc::Direction::NorthWest + 1> m_offsetDirections;
    std::string m_texturePath;

    Bounce m_bounce;
    Bounce m_pulse;
    Bounce m_fade;

    PainterShaderProgramPtr m_shader;
    TexturePtr m_texture;

    std::string m_name;

    std::vector<AttachedEffectPtr> m_effects;

    Point m_toPoint;

    struct CurveKey
    {
        float t;
        float value;
        uint8_t ease;
    };
    struct Motion
    {
        float vx{ 0 };
        float vy{ 0 };
        float gravity{ 0 };
        float spin{ 0 };
        bool active{ false };
    };

    bool m_layered{ false };
    bool m_additive{ false };
    bool m_flipped{ false };
    uint8_t m_framePlay{ FRAMES_OWN };
    uint16_t m_framePlayMs{ 0 };
    float m_rotation{ 0 };
    float m_layerFrom{ 0 };
    Point m_anchor;
    Motion m_motion;
    Timer m_layerTimer;
    std::array<std::vector<CurveKey>, CURVE_COUNT> m_curves;

    friend class Thing;
    friend class Creature;
    friend class AttachedEffectManager;
};
