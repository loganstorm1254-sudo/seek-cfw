/**
 * File: lightsConfig.h
 *
 * Crypto OS: use WireOS-style backpack lights (not Anki green).
 **/

namespace Anki {
namespace Vector {

  inline bool& _ankilights() {
    static bool value = false;
    return value;
  }

  inline bool& _userlights() {
    static bool value = false;
    return value;
  }

}
}
