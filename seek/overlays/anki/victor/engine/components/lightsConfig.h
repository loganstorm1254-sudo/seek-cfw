/**
 * File: lightsConfig.h
 *
 * DVT build: always use stock Anki backpack lights (green charging pulse),
 * never WireOS RGB charging / rainbow idle.
 **/

namespace Anki {
namespace Vector {

  inline bool& _ankilights() {
    // Always stock Anki green pack — never WireOS orange/red.
    static bool value = true;
    return value;
  }

  inline bool& _userlights() {
    // Never prefer /data custom packs over Anki stock on this DVT build.
    static bool value = false;
    return value;
  }

}
}
