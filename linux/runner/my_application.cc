#include "my_application.h"
#include "file_operations.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Files from a second launch ("Open with" while running), forwarded by
  // GApplication to this primary instance. Queued until Dart calls "ready".
  GtkWindow* window;
  FlMethodChannel* external_open_channel;
  FlValue* external_open_queue;
  gboolean external_open_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView *view)
{
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void external_open_method_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(fl_method_call_get_name(method_call), "ready") == 0) {
    self->external_open_ready = TRUE;
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(self->external_open_queue));
    g_clear_pointer(&self->external_open_queue, fl_value_unref);
    self->external_open_queue = fl_value_new_list();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void deliver_arguments(MyApplication* self, gchar** arguments) {
  g_autoptr(FlValue) list = fl_value_new_list();
  for (gchar** argument = arguments; argument && *argument; ++argument) {
    fl_value_append_take(list, fl_value_new_string(*argument));
  }
  g_autoptr(FlValue) payload = fl_value_new_map();
  fl_value_set_string(payload, "arguments", list);
  if (self->external_open_ready && self->external_open_channel) {
    fl_method_channel_invoke_method(self->external_open_channel, "open",
                                    payload, nullptr, nullptr, nullptr);
  } else {
    fl_value_append(self->external_open_queue, payload);
  }
}

// Implements GApplication::command_line: a second launch forwarded its
// arguments to this running instance.
static int my_application_command_line(GApplication* application,
                                       GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  int argc = 0;
  g_auto(GStrv) argv = g_application_command_line_get_arguments(command_line, &argc);
  if (argc > 1) deliver_arguments(self, argv + 1);
  if (self->window) gtk_window_present(self->window);
  return 0;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "CrispCloud");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "CrispCloud");
  }

  gtk_window_set_default_size(window, 1280, 720);
  self->window = window;

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  register_file_operations(fl_engine_get_binary_messenger(fl_view_get_engine(view)), GTK_WIDGET(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->external_open_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.crispcloud/external_open", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->external_open_channel, external_open_method_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    // No session bus (headless CI, some sandboxes): run as an independent
    // instance, as before single-instance support.
    g_clear_error(&error);
    g_application_set_flags(application, G_APPLICATION_NON_UNIQUE);
    if (!g_application_register(application, nullptr, &error)) {
      g_warning("Failed to register: %s", error->message);
      *exit_status = 1;
      return TRUE;
    }
  }

  // Already running: GApplication forwards this command line to the primary
  // instance (my_application_command_line) and this process exits.
  if (g_application_get_is_remote(application)) {
    return FALSE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->external_open_channel);
  g_clear_pointer(&self->external_open_queue, fl_value_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->external_open_queue = fl_value_new_list();
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     // One instance: later launches hand
                                     // their files to it (command_line).
                                     "flags", G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
