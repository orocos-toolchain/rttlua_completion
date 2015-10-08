cmake_minimum_required(VERSION 2.8.3)
project(rttlua_completion)

find_package(catkin REQUIRED)

find_package(Lua51 REQUIRED)

catkin_package(
  DEPENDS Lua51
)
catkin_add_env_hooks(10.rttlua_completion SHELLS sh DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/env-hooks)

#############
## Install ##
#############

# all install targets should use catkin DESTINATION variables
# See http://ros.org/doc/api/catkin/html/adv_user_guide/variables.html

# Copied from rtt/config/check_depend.cmake
FIND_PATH( READLINE_H readline/readline.h )
IF ( READLINE_H )
    MESSAGE("-- Looking for readline/readline.h - found")
    FIND_LIBRARY(READLINE_LIBRARY readline )
    # On win32, we need to look for both readline (release) and readlineD (debug)
    # to avoid mixing release/debug runtime libraries
    IF(WIN32)
        FIND_LIBRARY(READLINED_LIBRARY readlineD )
        IF(READLINE_LIBRARY AND READLINED_LIBRARY)
            SET(READLINE_LIBRARY
                optimized ${READLINE_LIBRARY}
                debug ${READLINED_LIBRARY})
        ENDIF()
        MESSAGE("READLINE_LIBRARY = ${READLINE_LIBRARY}")
    ENDIF(WIN32)
    SET( READLINE 1 CACHE INTERNAL "libreadline" )
    SET( READLINE_INCLUDE_DIR ${READLINE_H} )
ELSE ( READLINE_H  )
    MESSAGE("-- Looking for readline/readline.h - not found")
    SET( READLINE 0 CACHE INTERNAL "libreadline" )
ENDIF ( READLINE_H )

if(NOT READLINE)
  message(FATAL_ERROR "Could not find dependency readline")
endif()

include_directories(${LUA_INCLUDE_DIR} ${READLINE_INCLUDE_DIR})
add_library(readline SHARED readline.c)
target_link_libraries(readline ${LUA_LIBRARIES} ${READLINE_LIBRARY})
set_target_properties(readline PROPERTIES PREFIX "")

file(GLOB LUA_FILES "*.lua")
install(
  FILES ${LUA_FILES}
  DESTINATION ${CATKIN_GLOBAL_SHARE_DESTINATION}/lua/5.1/rttlua_completion/
)

install(
  TARGETS readline
  DESTINATION ${CATKIN_GLOBAL_SHARE_DESTINATION}/lua/5.1/rttlua_completion/
)

