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

#include "attachedeffect.h"

#include "animator.h"
#include "gameconfig.h"
#include "lightview.h"
#include "thingtype.h"
#include "thingtypemanager.h"
#include "framework/core/clock.h"
#include "framework/graphics/animatedtexture.h"
#include "framework/graphics/drawpoolmanager.h"
#include "framework/graphics/shadermanager.h"
#include "framework/graphics/texture.h"
#include "framework/graphics/texturemanager.h"

AttachedEffectPtr AttachedEffect::create(const uint16_t thingId, const ThingCategory category) {
    if (!g_things.isValidDatId(thingId, category)) {
        g_logger.error("AttachedEffectManager::getInstance({}, {}): invalid thing with id or category.", thingId, static_cast<uint8_t>(category));
        return nullptr;
    }

    const auto& obj = std::make_shared<AttachedEffect>();
    obj->m_thingId = thingId;
    obj->m_thingCategory = category;
    return obj;
}

AttachedEffectPtr AttachedEffect::clone()
{
    auto obj = std::make_shared<AttachedEffect>();
    *(obj.get()) = *this;

    obj->m_frame = 0;
    obj->m_animationTimer.restart();
    obj->m_layerTimer.restart();
    obj->m_bounce.timer.restart();
    obj->m_pulse.timer.restart();
    obj->m_fade.timer.restart();

    if (!obj->m_texturePath.empty()) {
        if ((obj->m_texture = g_textures.getTexture(obj->m_texturePath, obj->m_smooth))) {
            if (obj->m_texture->isAnimatedTexture()) {
                const auto& animatedTexture = std::static_pointer_cast<AnimatedTexture>(obj->m_texture);
                animatedTexture->setOnMap(true);
                animatedTexture->restart();
            }
        }
    }

    return obj;
}

int getBounce(const Bounce& bounce) {
    const auto minHeight = bounce.minHeight * g_drawPool.getScaleFactor();
    const auto height = bounce.height * g_drawPool.getScaleFactor();
    return minHeight + (height - std::abs(height - static_cast<int>(bounce.timer.ticksElapsed() / (bounce.speed / 100.f)) % static_cast<int>(height * 2)));
}

void AttachedEffect::draw(const Point& dest, const bool isOnTop, LightView* lightView, const bool drawThing) {
    if (m_transform)
        return;

    if (m_layered && m_texture) {
        if (m_offsetDirections[m_direction].onTop == isOnTop)
            drawLayer(dest, lightView, drawThing);
        return;
    }

    auto* thingType = getThingType();
    if (m_texture != nullptr || thingType != nullptr) {
        const auto& dirControl = m_offsetDirections[m_direction];
        if (dirControl.onTop != isOnTop)
            return;

        if (!m_canDrawOnUI && g_drawPool.getCurrentType() == DrawPoolType::FOREGROUND)
            return;

        const int animation = getCurrentAnimationPhase();
        if (m_loop > -1 && animation != m_lastAnimation) {
            m_lastAnimation = animation;
            if (animation == 0 && --m_loop == 0)
                return;
        }

        // Check if the thing type can actually be drawn before setting opacity/shader
        // This prevents stale state from affecting subsequent draws when this effect
        // returns early due to missing texture or invalid state
        if (!m_texture && thingType && (thingType->isNull() || thingType->getAnimationPhases() == 0))
            return;


        const auto scaleFactor = g_drawPool.getScaleFactor();

        // Only set shader, opacity, pulse and fade when actually drawing things
        // to prevent stale state from affecting subsequent draws
        if (drawThing) {
            if (m_shader) g_drawPool.setShaderProgram(m_shader, true);
            if (m_opacity < 100) g_drawPool.setOpacity(getOpacity(), true);

            if (m_pulse.height > 0 && m_pulse.speed > 0) {
                g_drawPool.setScaleFactor(scaleFactor + getBounce(m_pulse) / 100.f);
            }

            if (m_fade.height > 0 && m_fade.speed > 0) {
                g_drawPool.setOpacity(std::clamp<float>(getBounce(m_fade) / 100.f, 0, 1.f));
            }
        }

        auto point = dest - (dirControl.offset * g_drawPool.getScaleFactor());
        if (!m_toPoint.isNull()) {
            const float fraction = std::min<float>(m_animationTimer.ticksElapsed() / static_cast<float>(m_duration), 1.f);
            point += m_toPoint * fraction * g_drawPool.getScaleFactor();
        }

        if (m_bounce.height > 0 && m_bounce.speed > 0) {
            point -= getBounce(m_bounce);
        }

        if (lightView && m_light.intensity > 0)
            lightView->addLightSource(dest, m_light);

        auto lastDrawOrder = g_drawPool.getDrawOrder();
        if (g_drawPool.getCurrentType() == DrawPoolType::MAP)
            g_drawPool.setDrawOrder(getDrawOrder());

        if (m_texture) {
            if (drawThing) {
                const auto& size = (m_size.isUnset() ? m_texture->getSize() : m_size) * g_drawPool.getScaleFactor();
                const auto& texture = m_texture->isAnimatedTexture() ? std::static_pointer_cast<AnimatedTexture>(m_texture)->get(m_frame, m_animationTimer) : m_texture;
                const auto& rect = Rect(Point(), texture->getSize());

                g_drawPool.addTexturedRect(Rect(point, size), texture, rect, Color::white);
            }
        } else {
            thingType->draw(point, 0, m_direction, 0, 0, animation, Color::white, drawThing, lightView);
        }

        g_drawPool.setDrawOrder(lastDrawOrder);

        if (drawThing) {
            if (m_pulse.height > 0 && m_pulse.speed > 0) {
                g_drawPool.setScaleFactor(scaleFactor);
            }

            if (m_fade.height > 0 && m_fade.speed > 0) {
                g_drawPool.resetOpacity();
            }
        }
    }

    if (drawThing) {
        for (const auto& effect : m_effects)
            effect->draw(dest, isOnTop, lightView);
    }
}

void AttachedEffect::drawLight(const Point& dest, LightView* lightView) {
    if (!lightView) return;

    const auto& dirControl = m_offsetDirections[m_direction];
    draw(dest, dirControl.onTop, lightView, false);

    for (const auto& effect : m_effects)
        effect->drawLight(dest, lightView);
}

int AttachedEffect::getCurrentAnimationPhase()
{
    if (m_texture) {
        if (m_texture->isAnimatedTexture())
            std::static_pointer_cast<AnimatedTexture>(m_texture)->get(m_frame, m_animationTimer);
        return m_frame;
    }

    const auto thingType = getThingType();
    if (!thingType) return 0;

    const auto* animator = thingType->getIdleAnimator();
    if (!animator && thingType->isAnimateAlways())
        animator = thingType->getAnimator();

    if (animator)
        return animator->getPhaseAt(m_animationTimer, getSpeed());

    if (thingType->isEffect()) {
        const int animationPhases = thingType->getAnimationPhases();
        const float speed = getSpeed();
        if (animationPhases <= 0 || speed <= 0.f) return 0;

        const int lastPhase = animationPhases - 1;
        const int effectTicksPerFrame = g_gameConfig.getEffectTicksPerFrame();
        const int ticksPerFrame = std::max<int>(1, static_cast<int>(effectTicksPerFrame / speed));
        const int phase = std::min<int>(static_cast<int>(m_animationTimer.ticksElapsed() / ticksPerFrame), lastPhase);
        if (phase == lastPhase) m_animationTimer.restart();
        return phase;
    }

    if (thingType->isCreature() && thingType->isAnimateAlways()) {
        const int animationPhases = thingType->getAnimationPhases();
        const float speed = getSpeed();
        if (animationPhases <= 0 || speed <= 0.f) return 0;

        const int ticksPerFrame = std::max<int>(1, static_cast<int>(std::round((1000.0 / animationPhases) / speed)));
        const long long animationPeriod = static_cast<long long>(ticksPerFrame) * animationPhases;
        if (animationPeriod <= 0) return 0;

        return static_cast<int>((g_clock.millis() % animationPeriod) / ticksPerFrame);
    }

    return 0;
}

void AttachedEffect::setShader(const std::string_view name) { m_shader = g_shaders.getShader(name); }

void AttachedEffect::setCurve(const uint8_t channel, const std::vector<float>& keys)
{
    if (channel >= CURVE_COUNT)
        return;

    auto& curve = m_curves[channel];
    curve.clear();
    for (size_t i = 0; i + 2 < keys.size(); i += 3)
        curve.push_back({ .t = keys[i], .value = keys[i + 1], .ease = static_cast<uint8_t>(std::clamp<float>(keys[i + 2], EASE_LINEAR, EASE_OVERSHOOT)) });
    std::ranges::stable_sort(curve, {}, &CurveKey::t);

    // the layer comes in with the first key of any of its curves
    bool any = false;
    for (const auto& c : m_curves) {
        if (c.empty())
            continue;
        m_layerFrom = any ? std::min(m_layerFrom, c.front().t) : c.front().t;
        any = true;
    }
    m_layered = true;
}

namespace
{
    float easeLayerKey(const uint8_t kind, const float x)
    {
        switch (kind) {
            case AttachedEffect::EASE_IN: return x * x * x;
            case AttachedEffect::EASE_OUT: return 1.f - std::pow(1.f - x, 3.f);
            case AttachedEffect::EASE_IN_OUT: return x < 0.5f ? 4.f * x * x * x : 1.f - std::pow(-2.f * x + 2.f, 3.f) / 2.f;
            case AttachedEffect::EASE_OUT_STRONG: return x >= 1.f ? 1.f : 1.f - std::pow(2.f, -10.f * x);
            case AttachedEffect::EASE_OVERSHOOT: {
                constexpr float c1 = 1.70158f;
                constexpr float c3 = c1 + 1.f;
                return 1.f + c3 * std::pow(x - 1.f, 3.f) + c1 * std::pow(x - 1.f, 2.f);
            }
            default: return x;
        }
    }
}

float AttachedEffect::curveValue(const uint8_t channel, const float t, const float fallback) const
{
    const auto& curve = m_curves[channel];
    if (curve.empty())
        return fallback;
    if (t <= curve.front().t)
        return curve.front().value;
    if (t >= curve.back().t)
        return curve.back().value;

    // a handful of keys: a walk is as fast as a search
    size_t next = 1;
    while (curve[next].t < t)
        ++next;
    const auto& from = curve[next - 1];
    const auto& to = curve[next];
    const float span = to.t - from.t;
    const float x = span > 0.f ? (t - from.t) / span : 1.f;
    return from.value + (to.value - from.value) * easeLayerKey(to.ease, x);
}

TexturePtr AttachedEffect::layerTexture(const float t)
{
    if (!m_texture->isAnimatedTexture())
        return m_texture;

    const auto& animated = std::static_pointer_cast<AnimatedTexture>(m_texture);
    if (m_framePlay == FRAMES_OWN || m_framePlayMs == 0)
        return animated->get(m_frame, m_animationTimer);

    const auto count = animated->getFramesCount();
    const float progress = std::max(0.f, t - m_layerFrom) / m_framePlayMs;
    size_t index;
    switch (m_framePlay) {
        case FRAMES_LOOP:
            index = static_cast<size_t>(progress * count) % count;
            break;
        case FRAMES_CLOCK:
            // frame = floor((count - 1) * t / T): the last one only at T
            index = static_cast<size_t>((count - 1) * std::min(progress, 1.f));
            break;
        default:
            index = std::min(static_cast<size_t>(progress * count), count - 1);
            break;
    }
    return animated->getFrame(index);
}

void AttachedEffect::drawLayer(const Point& dest, LightView* lightView, const bool drawThing)
{
    const float t = static_cast<float>(m_layerTimer.ticksElapsed());
    if (t < m_layerFrom)
        return;

    // a particle sets off when it comes in
    const float seconds = (t - m_layerFrom) / 1000.f;
    float x = curveValue(CURVE_X, t, 0.f);
    float y = curveValue(CURVE_Y, t, 0.f);
    float angle = m_rotation + curveValue(CURVE_ROTATION, t, 0.f);
    if (m_motion.active) {
        x += m_motion.vx * seconds;
        y += m_motion.vy * seconds + m_motion.gravity * seconds * seconds / 2.f;
        angle += m_motion.spin * seconds;
    }

    // the anchor's place: where the image's top left would be (dest less
    // the offset) plus the anchor, then moved by the curves
    const float scaleFactor = g_drawPool.getScaleFactor();
    const auto& topLeft = dest - (m_offsetDirections[m_direction].offset * scaleFactor);
    const PointF pivot(topLeft.x + (m_anchor.x + x) * scaleFactor, topLeft.y + (m_anchor.y + y) * scaleFactor);

    if (lightView && !drawThing) {
        const float intensity = curveValue(CURVE_LIGHT, t, m_light.intensity);
        if (intensity >= 1.f) {
            Light light = m_light;
            light.intensity = static_cast<uint8_t>(std::min(intensity + 0.5f, 255.f));
            lightView->addLightSource(Point(pivot.x, pivot.y), light);
        }
        return;
    }
    if (!drawThing)
        return;

    const float opacity = std::clamp(curveValue(CURVE_OPACITY, t, 1.f), 0.f, 1.f) * getOpacity();
    const float scale = curveValue(CURVE_SCALE, t, 1.f);
    const float stretch = curveValue(CURVE_STRETCH, t, 1.f);
    if (opacity <= 0.004f || scale <= 0.f || stretch <= 0.f)
        return;

    const auto& texture = layerTexture(t);
    if (!texture)
        return;

    const auto& size = m_size.isUnset() ? m_texture->getSize() : m_size;
    const float scaleX = scale * stretch * scaleFactor;
    const float scaleY = scale * scaleFactor;
    const float anchorY = m_flipped ? size.height() - m_anchor.y : m_anchor.y;
    const Rect rect(static_cast<int>(std::round(pivot.x - m_anchor.x * scaleX)), static_cast<int>(std::round(pivot.y - anchorY * scaleY)),
                    std::max(1, static_cast<int>(std::round(size.width() * scaleX))), std::max(1, static_cast<int>(std::round(size.height() * scaleY))));

    const auto lastDrawOrder = g_drawPool.getDrawOrder();
    if (g_drawPool.getCurrentType() == DrawPoolType::MAP)
        g_drawPool.setDrawOrder(getDrawOrder());

    const bool turned = std::abs(angle) > 0.01f;
    if (turned) {
        g_drawPool.pushTransformMatrix();
        g_drawPool.rotate(pivot.x, pivot.y, angle * (Fw::pi / 180.f));
    }
    if (m_shader)
        g_drawPool.setShaderProgram(m_shader, true);
    if (opacity < 1.f)
        g_drawPool.setOpacity(opacity, true);
    if (m_additive)
        g_drawPool.setCompositionMode(CompositionMode::ADDITIVE, true);

    if (m_flipped)
        g_drawPool.addUpsideDownTexturedRect(rect, texture, Rect(Point(), texture->getSize()), Color::white);
    else
        g_drawPool.addTexturedRect(rect, texture, Rect(Point(), texture->getSize()), Color::white);

    if (turned)
        g_drawPool.popTransformMatrix();
    g_drawPool.setDrawOrder(lastDrawOrder);
}

void AttachedEffect::move(const Position& fromPosition, const Position& toPosition) {
    m_toPoint = Point(toPosition.x - fromPosition.x, toPosition.y - fromPosition.y) * g_gameConfig.getSpriteSize();
    m_animationTimer.restart();
}

ThingType* AttachedEffect::getThingType() const {
    return m_thingId > 0 ? g_things.getRawThingType(m_thingId, m_thingCategory) : nullptr;
}
