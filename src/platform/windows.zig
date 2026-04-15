const std = @import("std");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const LocationError = @import("../location.zig").LocationError;

// ---------------------------------------------------------------------------
// WinRT / COM base types
// ---------------------------------------------------------------------------

const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const HRESULT = i32;
const HSTRING = ?*anyopaque;

const S_OK: HRESULT = 0;
const E_ACCESSDENIED: HRESULT = @bitCast(@as(u32, 0x80070005));

const RO_INIT_MULTITHREADED: u32 = 1;

// AsyncStatus enum: 0=Started, 1=Completed, 2=Canceled, 3=Error
const AsyncStatus = enum(i32) {
    Started = 0,
    Completed = 1,
    Canceled = 2,
    Error = 3,
};

// GeolocationAccessStatus: 0=Unspecified, 1=Allowed, 2=Denied
const GeolocationAccessStatus = enum(i32) {
    Unspecified = 0,
    Allowed = 1,
    Denied = 2,
};

// ---------------------------------------------------------------------------
// Interface IIDs
// ---------------------------------------------------------------------------

// IID_IInspectable: {AF86E2E0-B12D-4C6A-9C5A-D7AA65101E90}
const IID_IInspectable = GUID{
    .data1 = 0xAF86E2E0,
    .data2 = 0xB12D,
    .data3 = 0x4C6A,
    .data4 = .{ 0x9C, 0x5A, 0xD7, 0xAA, 0x65, 0x10, 0x1E, 0x90 },
};

// IID_IGeolocator: {A9C3BF62-4524-4989-8AA9-DE019D2E551F}
const IID_IGeolocator = GUID{
    .data1 = 0xA9C3BF62,
    .data2 = 0x4524,
    .data3 = 0x4989,
    .data4 = .{ 0x8A, 0xA9, 0xDE, 0x01, 0x9D, 0x2E, 0x55, 0x1F },
};

// IID_IGeolocatorStatics: {9A8E7571-2DF5-4591-9F87-EB5FD894E9B7}
const IID_IGeolocatorStatics = GUID{
    .data1 = 0x9A8E7571,
    .data2 = 0x2DF5,
    .data3 = 0x4591,
    .data4 = .{ 0x9F, 0x87, 0xEB, 0x5F, 0xD8, 0x94, 0xE9, 0xB7 },
};

// IID_IGeoposition: {C18D0454-7D41-4FF7-A957-9DFFB4EF7F5B}
const IID_IGeoposition = GUID{
    .data1 = 0xC18D0454,
    .data2 = 0x7D41,
    .data3 = 0x4FF7,
    .data4 = .{ 0xA9, 0x57, 0x9D, 0xFF, 0xB4, 0xEF, 0x7F, 0x5B },
};

// IID_IGeocoordinate: {EE21A3AA-976A-4C70-803D-083EA55BCBC4}
const IID_IGeocoordinate = GUID{
    .data1 = 0xEE21A3AA,
    .data2 = 0x976A,
    .data3 = 0x4C70,
    .data4 = .{ 0x80, 0x3D, 0x08, 0x3E, 0xA5, 0x5B, 0xCB, 0xC4 },
};

// IID_IAsyncInfo: {00000036-0000-0000-C000-000000000046}
const IID_IAsyncInfo = GUID{
    .data1 = 0x00000036,
    .data2 = 0x0000,
    .data3 = 0x0000,
    .data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

// IID_IAsyncOperation<Geoposition>: {EE73ECF0-099D-57E5-8407-5B32E5AF1CC4}
const IID_IAsyncOperation_Geoposition = GUID{
    .data1 = 0xEE73ECF0,
    .data2 = 0x099D,
    .data3 = 0x57E5,
    .data4 = .{ 0x84, 0x07, 0x5B, 0x32, 0xE5, 0xAF, 0x1C, 0xC4 },
};

// IID_IAsyncOperation<GeolocationAccessStatus>: {DE2B24D0-B726-57B1-A7C5-E5A13932B7DE}
const IID_IAsyncOperation_AccessStatus = GUID{
    .data1 = 0xDE2B24D0,
    .data2 = 0xB726,
    .data3 = 0x57B1,
    .data4 = .{ 0xA7, 0xC5, 0xE5, 0xA1, 0x39, 0x32, 0xB7, 0xDE },
};

// ---------------------------------------------------------------------------
// COM vtable definitions
// ---------------------------------------------------------------------------
// WinRT interfaces: IUnknown (3) + IInspectable (3) + interface methods

const IInspectableVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    // IInspectable
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
};

const IGeolocatorVtbl = extern struct {
    // IUnknown (3) + IInspectable (3)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IGeolocator methods
    get_DesiredAccuracy: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    put_DesiredAccuracy: *const fn (*anyopaque, i32) callconv(.c) HRESULT,
    get_MovementThreshold: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    put_MovementThreshold: *const fn (*anyopaque, f64) callconv(.c) HRESULT,
    get_ReportInterval: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    put_ReportInterval: *const fn (*anyopaque, u32) callconv(.c) HRESULT,
    get_LocationStatus: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    GetGeopositionAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetGeopositionAsyncWithAgeAndTimeout: *const fn (*anyopaque, i64, i64, *?*anyopaque) callconv(.c) HRESULT,
    add_PositionChanged: *const fn (*anyopaque, *anyopaque, *i64) callconv(.c) HRESULT,
    remove_PositionChanged: *const fn (*anyopaque, i64) callconv(.c) HRESULT,
    add_StatusChanged: *const fn (*anyopaque, *anyopaque, *i64) callconv(.c) HRESULT,
    remove_StatusChanged: *const fn (*anyopaque, i64) callconv(.c) HRESULT,
};

const IGeolocatorStaticsVtbl = extern struct {
    // IUnknown (3) + IInspectable (3)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IGeolocatorStatics methods
    RequestAccessAsync: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetGeopositionHistoryAsync: *const fn (*anyopaque, i64, *?*anyopaque) callconv(.c) HRESULT,
    GetGeopositionHistoryAsyncWithDuration: *const fn (*anyopaque, i64, i64, *?*anyopaque) callconv(.c) HRESULT,
};

const IAsyncInfoVtbl = extern struct {
    // IUnknown (3) + IInspectable (3)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IAsyncInfo methods
    get_Id: *const fn (*anyopaque, *u32) callconv(.c) HRESULT,
    get_Status: *const fn (*anyopaque, *AsyncStatus) callconv(.c) HRESULT,
    get_ErrorCode: *const fn (*anyopaque, *HRESULT) callconv(.c) HRESULT,
    Cancel: *const fn (*anyopaque) callconv(.c) HRESULT,
    Close: *const fn (*anyopaque) callconv(.c) HRESULT,
};

// IAsyncOperation<Geoposition> — GetResults returns an IInspectable* (IGeoposition)
const IAsyncOperation_GeopositionVtbl = extern struct {
    // IUnknown (3) + IInspectable (3)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IAsyncOperation methods
    put_Completed: *const fn (*anyopaque, ?*anyopaque) callconv(.c) HRESULT,
    get_Completed: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetResults: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

// IAsyncOperation<GeolocationAccessStatus> — GetResults returns an enum value
const IAsyncOperation_AccessStatusVtbl = extern struct {
    // IUnknown (3) + IInspectable (3)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IAsyncOperation methods
    put_Completed: *const fn (*anyopaque, ?*anyopaque) callconv(.c) HRESULT,
    get_Completed: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    GetResults: *const fn (*anyopaque, *GeolocationAccessStatus) callconv(.c) HRESULT,
};

const IGeopositionVtbl = extern struct {
    // IUnknown (3) + IInspectable (3)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IGeoposition methods
    get_Coordinate: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_CivicAddress: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
};

const IGeocoordinateVtbl = extern struct {
    // IUnknown (3) + IInspectable (3)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.c) u32,
    Release: *const fn (*anyopaque) callconv(.c) u32,
    GetIids: *const fn (*anyopaque, *u32, *?[*]GUID) callconv(.c) HRESULT,
    GetRuntimeClassName: *const fn (*anyopaque, *HSTRING) callconv(.c) HRESULT,
    GetTrustLevel: *const fn (*anyopaque, *i32) callconv(.c) HRESULT,
    // IGeocoordinate methods
    get_Latitude: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    get_Longitude: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    get_Altitude: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Accuracy: *const fn (*anyopaque, *f64) callconv(.c) HRESULT,
    get_AltitudeAccuracy: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Heading: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Speed: *const fn (*anyopaque, *?*anyopaque) callconv(.c) HRESULT,
    get_Timestamp: *const fn (*anyopaque, *i64) callconv(.c) HRESULT,
};

// Typed wrappers — vtable pointer is always the first field
const ComObj = extern struct { vtable: *const anyopaque };

fn vtable(comptime VtblType: type, obj: *anyopaque) *const VtblType {
    const ptr: *const *const VtblType = @ptrCast(@alignCast(obj));
    return ptr.*;
}

fn release(obj: *anyopaque) void {
    const vt: *const IInspectableVtbl = vtable(IInspectableVtbl, obj);
    _ = vt.Release(obj);
}

fn queryInterface(obj: *anyopaque, iid: *const GUID) ?*anyopaque {
    const vt: *const IInspectableVtbl = vtable(IInspectableVtbl, obj);
    var result: ?*anyopaque = null;
    const hr = vt.QueryInterface(obj, iid, &result);
    if (hr == S_OK) return result;
    return null;
}

// ---------------------------------------------------------------------------
// WinRT extern functions
// ---------------------------------------------------------------------------

extern "api-ms-win-core-winrt-l1-1-0" fn RoInitialize(init_type: u32) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-l1-1-0" fn RoUninitialize() callconv(.c) void;
extern "api-ms-win-core-winrt-l1-1-0" fn RoActivateInstance(
    class_id: HSTRING,
    instance: *?*anyopaque,
) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-l1-1-0" fn RoGetActivationFactory(
    class_id: HSTRING,
    iid: *const GUID,
    factory: *?*anyopaque,
) callconv(.c) HRESULT;

extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsCreateString(
    source: [*]const u16,
    length: u32,
    string: *HSTRING,
) callconv(.c) HRESULT;
extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsDeleteString(
    string: HSTRING,
) callconv(.c) HRESULT;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const GEOLOCATOR_CLASS = [_]u16{
    'W', 'i', 'n', 'd', 'o', 'w', 's', '.', 'D', 'e', 'v', 'i', 'c', 'e', 's',
    '.', 'G', 'e', 'o', 'l', 'o', 'c', 'a', 't', 'i', 'o', 'n', '.', 'G', 'e',
    'o', 'l', 'o', 'c', 'a', 't', 'o', 'r',
};

/// Poll an IAsyncInfo until it completes or times out.
fn waitForAsync(async_obj: *anyopaque, timeout_ms: u32) !AsyncStatus {
    const info = queryInterface(async_obj, &IID_IAsyncInfo) orelse
        return LocationError.LocationUnavailable;
    defer release(info);

    const info_vt = vtable(IAsyncInfoVtbl, info);
    const timeout_ns: i128 = @as(i128, timeout_ms) * std.time.ns_per_ms;
    const start: i128 = std.time.nanoTimestamp();

    while (true) {
        var status: AsyncStatus = .Started;
        _ = info_vt.get_Status(info, &status);
        if (status != .Started) return status;

        const now: i128 = std.time.nanoTimestamp();
        if (now - start >= timeout_ns) return LocationError.Timeout;

        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;

    // Initialize WinRT
    const hr_init = RoInitialize(RO_INIT_MULTITHREADED);
    // S_OK or S_FALSE (already initialized) are both fine
    if (hr_init != S_OK and hr_init != @as(HRESULT, 1)) {
        return LocationError.LocationUnavailable;
    }
    defer RoUninitialize();

    // Create HSTRING for class name
    var class_name: HSTRING = null;
    if (WindowsCreateString(&GEOLOCATOR_CLASS, GEOLOCATOR_CLASS.len, &class_name) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    defer _ = WindowsDeleteString(class_name);

    // Request location permission via IGeolocatorStatics.RequestAccessAsync
    var statics_ptr: ?*anyopaque = null;
    if (RoGetActivationFactory(class_name, &IID_IGeolocatorStatics, &statics_ptr) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const statics = statics_ptr.?;
    defer release(statics);

    const statics_vt = vtable(IGeolocatorStaticsVtbl, statics);
    var access_async_ptr: ?*anyopaque = null;
    if (statics_vt.RequestAccessAsync(statics, &access_async_ptr) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const access_async = access_async_ptr.?;
    defer release(access_async);

    // Wait for permission result
    const access_status = try waitForAsync(access_async, timeout_ms);
    if (access_status != .Completed) {
        return LocationError.LocationUnavailable;
    }

    // Get the access result via IAsyncOperation<GeolocationAccessStatus>
    const access_op = queryInterface(access_async, &IID_IAsyncOperation_AccessStatus) orelse
        return LocationError.LocationUnavailable;
    defer release(access_op);

    const access_op_vt = vtable(IAsyncOperation_AccessStatusVtbl, access_op);
    var access_result: GeolocationAccessStatus = .Unspecified;
    if (access_op_vt.GetResults(access_op, &access_result) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    if (access_result != .Allowed) {
        return LocationError.PermissionDenied;
    }

    // Activate Geolocator instance
    var inspectable_ptr: ?*anyopaque = null;
    if (RoActivateInstance(class_name, &inspectable_ptr) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const inspectable = inspectable_ptr.?;
    defer release(inspectable);

    // QueryInterface for IGeolocator
    const geolocator = queryInterface(inspectable, &IID_IGeolocator) orelse
        return LocationError.LocationUnavailable;
    defer release(geolocator);

    // Set high accuracy
    const geo_vt = vtable(IGeolocatorVtbl, geolocator);
    _ = geo_vt.put_DesiredAccuracy(geolocator, 0); // PositionAccuracy.High = 0

    // Call GetGeopositionAsync
    var geo_async_ptr: ?*anyopaque = null;
    if (geo_vt.GetGeopositionAsync(geolocator, &geo_async_ptr) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const geo_async = geo_async_ptr.?;
    defer release(geo_async);

    // Wait for position result
    const geo_status = try waitForAsync(geo_async, timeout_ms);
    if (geo_status != .Completed) {
        if (geo_status == .Error) return LocationError.LocationUnavailable;
        return LocationError.Timeout;
    }

    // Get IAsyncOperation<Geoposition> and call GetResults
    const geo_op = queryInterface(geo_async, &IID_IAsyncOperation_Geoposition) orelse
        return LocationError.LocationUnavailable;
    defer release(geo_op);

    const geo_op_vt = vtable(IAsyncOperation_GeopositionVtbl, geo_op);
    var position_ptr: ?*anyopaque = null;
    if (geo_op_vt.GetResults(geo_op, &position_ptr) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const position = position_ptr.?;
    defer release(position);

    // QI for IGeoposition
    const geoposition = queryInterface(position, &IID_IGeoposition) orelse
        return LocationError.LocationUnavailable;
    defer release(geoposition);

    // Get coordinate
    const pos_vt = vtable(IGeopositionVtbl, geoposition);
    var coord_ptr: ?*anyopaque = null;
    if (pos_vt.get_Coordinate(geoposition, &coord_ptr) != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const coord = coord_ptr.?;
    defer release(coord);

    // QI for IGeocoordinate
    const geocoord = queryInterface(coord, &IID_IGeocoordinate) orelse
        return LocationError.LocationUnavailable;
    defer release(geocoord);

    // Extract lat, lon, accuracy
    const coord_vt = vtable(IGeocoordinateVtbl, geocoord);
    var lat: f64 = 0;
    var lon: f64 = 0;
    var accuracy: f64 = 0;

    if (coord_vt.get_Latitude(geocoord, &lat) != S_OK) return LocationError.LocationUnavailable;
    if (coord_vt.get_Longitude(geocoord, &lon) != S_OK) return LocationError.LocationUnavailable;
    _ = coord_vt.get_Accuracy(geocoord, &accuracy);

    return Location{
        .latitude = lat,
        .longitude = lon,
        .accuracy = accuracy,
    };
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
