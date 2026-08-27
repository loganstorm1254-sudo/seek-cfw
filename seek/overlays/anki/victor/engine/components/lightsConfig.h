/**
 * File: lightsConfig.h
 *
 * DVT: Anki green backpack lights (not WireOS RGB).
 **/

namespace Anki {
namespace Vector {

  inline bool& _ankilights() {
    static bool value = true;
    return value;
  }

  inline bool& _userlights() {
    static bool value = false;
    return value;
  }

}
}
