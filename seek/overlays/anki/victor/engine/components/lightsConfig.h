/**
 * File: lightsConfig.h
 *
 * DVT build: always use stock Anki backpack lights (green charging pulse),
 * never WireOS RGB charging / rainbow idle.
 **/

#include <sys/stat.h>

namespace Anki {
namespace Vector {

  inline bool& _ankilights() {
    static bool value = true;
    return value;
  }

  inline bool& _userlights() {
    static bool initialized = false;
    static bool value = false;

    if (!initialized) {
      struct stat buffer;
      value = (stat("/data/data/customBackpackLights/off.json", &buffer) == 0);
      initialized = true;
    }

    return value;
  }

}
}
