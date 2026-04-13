const std = @import("std");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const LocationError = @import("../location.zig").LocationError;

// ---------------------------------------------------------------------------
// D-Bus type definitions and extern declarations
// ---------------------------------------------------------------------------

const DBusConnection = opaque {};
const DBusMessage = opaque {};

// DBusError — the dummy1-5 fields are bitfields (1 bit each) packed into
// a single unsigned int. In Zig we represent the packed bits as one c_uint.
const DBusError = extern struct {
    name: ?[*:0]const u8,
    message: ?[*:0]const u8,
    dummy_bits: c_uint, // 5 single-bit fields packed into one uint
    padding1: ?*anyopaque,
};

const DBusMessageIter = extern struct {
    data: [14]?*anyopaque,
};

const DBUS_BUS_SYSTEM: c_int = 1;
const DBUS_TYPE_STRING: c_int = 's';
const DBUS_TYPE_VARIANT: c_int = 'v';
const DBUS_TYPE_DOUBLE: c_int = 'd';
const DBUS_TYPE_UINT32: c_int = 'u';
const DBUS_TYPE_OBJECT_PATH: c_int = 'o';

extern "c" fn dbus_error_init(err: *DBusError) void;
extern "c" fn dbus_error_free(err: *DBusError) void;
extern "c" fn dbus_error_is_set(err: *const DBusError) c_uint;
extern "c" fn dbus_bus_get(bus_type: c_int, err: *DBusError) ?*DBusConnection;
extern "c" fn dbus_bus_add_match(conn: *DBusConnection, rule: [*:0]const u8, err: *DBusError) void;
extern "c" fn dbus_connection_unref(conn: *DBusConnection) void;
extern "c" fn dbus_connection_read_write_dispatch(conn: *DBusConnection, timeout_ms: c_int) c_uint;
extern "c" fn dbus_connection_pop_message(conn: *DBusConnection) ?*DBusMessage;
extern "c" fn dbus_message_new_method_call(
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface: [*:0]const u8,
    method: [*:0]const u8,
) ?*DBusMessage;
extern "c" fn dbus_message_is_signal(msg: *DBusMessage, iface: [*:0]const u8, name: [*:0]const u8) c_uint;
extern "c" fn dbus_connection_send_with_reply_and_block(
    conn: *DBusConnection,
    msg: *DBusMessage,
    timeout: c_int,
    err: *DBusError,
) ?*DBusMessage;
extern "c" fn dbus_message_iter_init(msg: *DBusMessage, iter: *DBusMessageIter) c_uint;
extern "c" fn dbus_message_iter_get_basic(iter: *DBusMessageIter, value: *anyopaque) void;
extern "c" fn dbus_message_iter_recurse(iter: *DBusMessageIter, sub: *DBusMessageIter) void;
extern "c" fn dbus_message_iter_next(iter: *DBusMessageIter) c_uint;
extern "c" fn dbus_message_iter_init_append(msg: *DBusMessage, iter: *DBusMessageIter) void;
extern "c" fn dbus_message_iter_append_basic(iter: *DBusMessageIter, arg_type: c_int, value: *const anyopaque) c_uint;
extern "c" fn dbus_message_iter_open_container(
    iter: *DBusMessageIter,
    container_type: c_int,
    contained_sig: ?[*:0]const u8,
    sub: *DBusMessageIter,
) c_uint;
extern "c" fn dbus_message_iter_close_container(iter: *DBusMessageIter, sub: *DBusMessageIter) c_uint;
extern "c" fn dbus_message_unref(msg: *DBusMessage) void;

// ---------------------------------------------------------------------------
// D-Bus helpers
// ---------------------------------------------------------------------------

const GEOCLUE_DEST = "org.freedesktop.GeoClue2";
const GEOCLUE_MANAGER_PATH = "/org/freedesktop/GeoClue2/Manager";
const GEOCLUE_MANAGER_IFACE = "org.freedesktop.GeoClue2.Manager";
const GEOCLUE_CLIENT_IFACE = "org.freedesktop.GeoClue2.Client";
const GEOCLUE_LOCATION_IFACE = "org.freedesktop.GeoClue2.Location";
const DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

/// Call a D-Bus method that returns an object path string.
/// Returns a heap-allocated copy (caller must free with c_allocator).
/// The D-Bus reply is unreffed before returning, so the string must be copied.
fn callMethodGetObjectPath(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface: [*:0]const u8,
    method: [*:0]const u8,
    err: *DBusError,
) ?[*:0]const u8 {
    const msg = dbus_message_new_method_call(dest, path, iface, method) orelse return null;
    defer dbus_message_unref(msg);

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err) orelse return null;
    defer dbus_message_unref(reply);

    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(reply, &iter) == 0) return null;

    var raw_path: [*:0]const u8 = undefined;
    dbus_message_iter_get_basic(&iter, @ptrCast(&raw_path));

    // Copy the string — the original points into the reply message's buffer
    // which becomes invalid after dbus_message_unref.
    const len = std.mem.len(raw_path);
    const copy = std.heap.c_allocator.allocSentinel(u8, len, 0) catch return null;
    @memcpy(copy[0..len], raw_path[0..len]);
    return copy;
}

/// Set a string property via org.freedesktop.DBus.Properties.Set
fn setStringProperty(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface_name: [*:0]const u8,
    prop_name: [*:0]const u8,
    value: [*:0]const u8,
    err: *DBusError,
) bool {
    const msg = dbus_message_new_method_call(dest, path, DBUS_PROPERTIES_IFACE, "Set") orelse return false;
    defer dbus_message_unref(msg);

    var args: DBusMessageIter = undefined;
    dbus_message_iter_init_append(msg, &args);

    // Append interface name (string)
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&iface_name));
    // Append property name (string)
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&prop_name));

    // Append variant containing the string value
    var variant: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&args, DBUS_TYPE_VARIANT, "s", &variant);
    _ = dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, @ptrCast(&value));
    _ = dbus_message_iter_close_container(&args, &variant);

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err);
    if (reply) |r| dbus_message_unref(r);
    return dbus_error_is_set(err) == 0;
}

/// Set a uint32 property via org.freedesktop.DBus.Properties.Set
fn setUint32Property(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface_name: [*:0]const u8,
    prop_name: [*:0]const u8,
    value: u32,
    err: *DBusError,
) bool {
    const msg = dbus_message_new_method_call(dest, path, DBUS_PROPERTIES_IFACE, "Set") orelse return false;
    defer dbus_message_unref(msg);

    var args: DBusMessageIter = undefined;
    dbus_message_iter_init_append(msg, &args);

    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&iface_name));
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&prop_name));

    var variant: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&args, DBUS_TYPE_VARIANT, "u", &variant);
    _ = dbus_message_iter_append_basic(&variant, DBUS_TYPE_UINT32, @ptrCast(&value));
    _ = dbus_message_iter_close_container(&args, &variant);

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err);
    if (reply) |r| dbus_message_unref(r);
    return dbus_error_is_set(err) == 0;
}

/// Get a double property via org.freedesktop.DBus.Properties.Get
fn getDoubleProperty(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface_name: [*:0]const u8,
    prop_name: [*:0]const u8,
    err: *DBusError,
) ?f64 {
    const msg = dbus_message_new_method_call(dest, path, DBUS_PROPERTIES_IFACE, "Get") orelse return null;
    defer dbus_message_unref(msg);

    var args: DBusMessageIter = undefined;
    dbus_message_iter_init_append(msg, &args);
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&iface_name));
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&prop_name));

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err) orelse return null;
    defer dbus_message_unref(reply);

    // Reply is a variant containing the double
    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(reply, &iter) == 0) return null;

    var variant_iter: DBusMessageIter = undefined;
    dbus_message_iter_recurse(&iter, &variant_iter);

    var result: f64 = 0;
    dbus_message_iter_get_basic(&variant_iter, @ptrCast(&result));
    return result;
}

/// Call a void method (no arguments, no meaningful return)
fn callVoidMethod(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface: [*:0]const u8,
    method: [*:0]const u8,
    err: *DBusError,
) void {
    const msg = dbus_message_new_method_call(dest, path, iface, method) orelse return;
    defer dbus_message_unref(msg);
    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err);
    if (reply) |r| dbus_message_unref(r);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;

    var err: DBusError = undefined;
    dbus_error_init(&err);
    defer dbus_error_free(&err);

    // Connect to system bus
    const conn = dbus_bus_get(DBUS_BUS_SYSTEM, &err) orelse {
        return LocationError.LocationUnavailable;
    };
    // Note: don't unref a shared connection from dbus_bus_get

    // Create a GeoClue2 client
    const client_path = callMethodGetObjectPath(
        conn,
        GEOCLUE_DEST,
        GEOCLUE_MANAGER_PATH,
        GEOCLUE_MANAGER_IFACE,
        "CreateClient",
        &err,
    ) orelse {
        return LocationError.LocationUnavailable;
    };

    // Set DesktopId
    _ = setStringProperty(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "DesktopId", "whereami", &err);

    // Set RequestedAccuracyLevel to EXACT (8)
    _ = setUint32Property(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "RequestedAccuracyLevel", 8, &err);

    // Subscribe to LocationUpdated signal
    dbus_bus_add_match(
        conn,
        "type='signal',interface='org.freedesktop.GeoClue2.Client',member='LocationUpdated'",
        &err,
    );

    // Start location acquisition
    callVoidMethod(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "Start", &err);
    if (dbus_error_is_set(&err) != 0) {
        // Check if it's a permission error
        if (err.name) |name| {
            const name_slice = std.mem.span(name);
            if (std.mem.indexOf(u8, name_slice, "AccessDenied") != null) {
                return LocationError.PermissionDenied;
            }
        }
        return LocationError.LocationUnavailable;
    }

    // Wait for LocationUpdated signal
    const timeout_per_poll: c_int = 1000; // 1 second per dispatch loop
    var remaining_ms: i64 = @intCast(timeout_ms);

    while (remaining_ms > 0) {
        const poll_timeout: c_int = if (remaining_ms < timeout_per_poll) @intCast(remaining_ms) else timeout_per_poll;
        _ = dbus_connection_read_write_dispatch(conn, poll_timeout);
        remaining_ms -= poll_timeout;

        // Check for messages
        while (dbus_connection_pop_message(conn)) |msg| {
            defer dbus_message_unref(msg);

            if (dbus_message_is_signal(msg, GEOCLUE_CLIENT_IFACE, "LocationUpdated") != 0) {
                // Signal args: (old_path: object_path, new_path: object_path)
                var iter: DBusMessageIter = undefined;
                if (dbus_message_iter_init(msg, &iter) == 0) continue;

                // Skip old_path
                _ = dbus_message_iter_next(&iter);

                // Get new_path (the location object path)
                var location_path: [*:0]const u8 = undefined;
                dbus_message_iter_get_basic(&iter, @ptrCast(&location_path));

                // Read properties from the location object
                const lat = getDoubleProperty(conn, GEOCLUE_DEST, location_path, GEOCLUE_LOCATION_IFACE, "Latitude", &err) orelse continue;
                const lon = getDoubleProperty(conn, GEOCLUE_DEST, location_path, GEOCLUE_LOCATION_IFACE, "Longitude", &err) orelse continue;
                const accuracy = getDoubleProperty(conn, GEOCLUE_DEST, location_path, GEOCLUE_LOCATION_IFACE, "Accuracy", &err) orelse 0;

                // Stop the client
                callVoidMethod(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "Stop", &err);

                return Location{
                    .latitude = lat,
                    .longitude = lon,
                    .accuracy = accuracy,
                };
            }
        }
    }

    // Timeout — stop client before returning
    callVoidMethod(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "Stop", &err);
    return LocationError.Timeout;
}

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    return null;
}

pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void {
    _ = allocator;
    _ = address;
}
