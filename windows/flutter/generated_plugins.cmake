#
# Generated file, do not edit.
#

list(APPEND FLUTTER_PLUGIN_LIST
  agora_rtc_engine
  audioplayers_windows
  connectivity_plus
  desktop_drop
  emoji_picker_flutter
  file_selector_windows
  firebase_core
  flutter_secure_storage_windows
  flutter_webrtc
  gal
  geolocator_windows
  hotkey_manager_windows
  iris_method_channel
  isar_flutter_libs
  livekit_client
  local_auth_windows
  pasteboard
  permission_handler_windows
  record_windows
  screen_retriever
  share_plus
  speech_to_text_windows
  tray_manager
  url_launcher_windows
  video_player_win
  webview_flutter_windows
  window_manager
)

list(APPEND FLUTTER_FFI_PLUGIN_LIST
  flutter_local_notifications_windows
  jni
)

set(PLUGIN_BUNDLED_LIBRARIES)

foreach(plugin ${FLUTTER_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${plugin}/windows plugins/${plugin})
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES $<TARGET_FILE:${plugin}_plugin>)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${plugin}_bundled_libraries})
endforeach(plugin)

foreach(ffi_plugin ${FLUTTER_FFI_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${ffi_plugin}/windows plugins/${ffi_plugin})
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${ffi_plugin}_bundled_libraries})
endforeach(ffi_plugin)
