const std = @import("std");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const LocationError = @import("../location.zig").LocationError;

// ---------------------------------------------------------------------------
// Win32 COM type definitions
// ---------------------------------------------------------------------------

const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const HRESULT = i32;

const S_OK: HRESULT = 0;
const S_FALSE: HRESULT = 1;
const E_ACCESSDENIED: HRESULT = @bitCast(@as(u32, 0x80070005));

const COINIT_APARTMENTTHREADED: u32 = 0x2;
const CLSCTX_INPROC_SERVER: u32 = 0x1;
const LOCATION_DESIRED_ACCURACY_HIGH: u32 = 0;

// CLSID_Location: {E5B8E079-EE6D-4E33-A438-C87F2E959254}
const CLSID_Location = GUID{
    .data1 = 0xE5B8E079,
    .data2 = 0xEE6D,
    .data3 = 0x4E33,
    .data4 = .{ 0xA4, 0x38, 0xC8, 0x7F, 0x2E, 0x95, 0x92, 0x54 },
};

// IID_ILocation: {AB2ECE69-56D9-4F28-B525-DE1B0EE44237}
const IID_ILocation = GUID{
    .data1 = 0xAB2ECE69,
    .data2 = 0x56D9,
    .data3 = 0x4F28,
    .data4 = .{ 0xB5, 0x25, 0xDE, 0x1B, 0x0E, 0xE4, 0x42, 0x37 },
};

// IID_ILatLongReport: {7FED806D-0EF8-4F07-80AC-36A0BEAE3134}
const IID_ILatLongReport = GUID{
    .data1 = 0x7FED806D,
    .data2 = 0x0EF8,
    .data3 = 0x4F07,
    .data4 = .{ 0x80, 0xAC, 0x36, 0xA0, 0xBE, 0xAE, 0x31, 0x34 },
};

// --- COM vtable definitions ---
// COM vtables are position-sensitive. Every slot must be present with correct types.

const ILocationVtbl = extern struct {
    // IUnknown (3 methods)
    QueryInterface: *const fn (*ILocation, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILocation) callconv(.c) u32,
    Release: *const fn (*ILocation) callconv(.c) u32,
    // ILocation (9 methods)
    RegisterForReport: *const fn (*ILocation, *anyopaque, *const GUID, u32) callconv(.c) HRESULT,
    UnregisterForReport: *const fn (*ILocation, *const GUID) callconv(.c) HRESULT,
    GetReport: *const fn (*ILocation, *const GUID, **ILocationReport) callconv(.c) HRESULT,
    GetReportStatus: *const fn (*ILocation, *const GUID, *u32) callconv(.c) HRESULT,
    GetReportInterval: *const fn (*ILocation, *const GUID, *u32) callconv(.c) HRESULT,
    SetReportInterval: *const fn (*ILocation, *const GUID, u32) callconv(.c) HRESULT,
    GetDesiredAccuracy: *const fn (*ILocation, *const GUID, *u32) callconv(.c) HRESULT,
    SetDesiredAccuracy: *const fn (*ILocation, *const GUID, u32) callconv(.c) HRESULT,
    RequestPermissions: *const fn (*ILocation, ?*anyopaque, [*]const GUID, u32, i32) callconv(.c) HRESULT,
};

const ILocation = extern struct {
    vtable: *const ILocationVtbl,
};

const ILocationReportVtbl = extern struct {
    // IUnknown (3)
    QueryInterface: *const fn (*ILocationReport, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILocationReport) callconv(.c) u32,
    Release: *const fn (*ILocationReport) callconv(.c) u32,
    // ILocationReport (4)
    GetSensorID: *const fn (*ILocationReport, *GUID) callconv(.c) HRESULT,
    GetTimestamp: *const fn (*ILocationReport, *anyopaque) callconv(.c) HRESULT,
    GetValue: *const fn (*ILocationReport, *const anyopaque, *anyopaque) callconv(.c) HRESULT,
    GetPropertyStoreIterator: *const fn (*ILocationReport, **anyopaque) callconv(.c) HRESULT,
};

const ILocationReport = extern struct {
    vtable: *const ILocationReportVtbl,
};

const ILatLongReportVtbl = extern struct {
    // IUnknown (3)
    QueryInterface: *const fn (*ILatLongReport, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILatLongReport) callconv(.c) u32,
    Release: *const fn (*ILatLongReport) callconv(.c) u32,
    // ILocationReport (4)
    GetSensorID: *const fn (*ILatLongReport, *GUID) callconv(.c) HRESULT,
    GetTimestamp: *const fn (*ILatLongReport, *anyopaque) callconv(.c) HRESULT,
    GetValue: *const fn (*ILatLongReport, *const anyopaque, *anyopaque) callconv(.c) HRESULT,
    GetPropertyStoreIterator: *const fn (*ILatLongReport, **anyopaque) callconv(.c) HRESULT,
    // ILatLongReport (4)
    GetLatitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetLongitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetAltitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetErrorRadius: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
};

const ILatLongReport = extern struct {
    vtable: *const ILatLongReportVtbl,
};

// ---------------------------------------------------------------------------
// Win32 COM extern functions
// ---------------------------------------------------------------------------

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, co_init: u32) callconv(.c) HRESULT;
extern "ole32" fn CoCreateInstance(
    clsid: *const GUID,
    outer: ?*anyopaque,
    cls_context: u32,
    iid: *const GUID,
    ppv: **anyopaque,
) callconv(.c) HRESULT;
extern "ole32" fn CoUninitialize() callconv(.c) void;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;

    // Initialize COM
    const hr_init = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
    if (hr_init != S_OK and hr_init != S_FALSE) {
        return LocationError.LocationUnavailable;
    }
    defer CoUninitialize();

    // Create ILocation instance
    var location_ptr: *anyopaque = undefined;
    const hr_create = CoCreateInstance(
        &CLSID_Location,
        null,
        CLSCTX_INPROC_SERVER,
        &IID_ILocation,
        &location_ptr,
    );
    if (hr_create != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const loc: *ILocation = @ptrCast(@alignCast(location_ptr));
    defer _ = loc.vtable.Release(loc);

    // Set desired accuracy
    _ = loc.vtable.SetDesiredAccuracy(loc, &IID_ILatLongReport, LOCATION_DESIRED_ACCURACY_HIGH);

    // Request permissions (blocking — waits for user response)
    const report_types = [_]GUID{IID_ILatLongReport};
    const hr_perm = loc.vtable.RequestPermissions(loc, null, &report_types, 1, 1); // fWaitForPermission=TRUE
    if (hr_perm == E_ACCESSDENIED) {
        return LocationError.PermissionDenied;
    }

    // Poll for a location report with timeout
    const timeout_ns: i128 = @as(i128, timeout_ms) * std.time.ns_per_ms;
    const start: i128 = std.time.nanoTimestamp();

    while (true) {
        var report_ptr: *ILocationReport = undefined;
        const hr_report = loc.vtable.GetReport(loc, &IID_ILatLongReport, &report_ptr);

        if (hr_report == S_OK) {
            defer _ = report_ptr.vtable.Release(report_ptr);

            // QueryInterface to ILatLongReport
            var latlng_ptr: *anyopaque = undefined;
            const hr_qi = report_ptr.vtable.QueryInterface(report_ptr, &IID_ILatLongReport, &latlng_ptr);
            if (hr_qi == S_OK) {
                const latlng: *ILatLongReport = @ptrCast(@alignCast(latlng_ptr));
                defer _ = latlng.vtable.Release(latlng);

                var lat: f64 = 0;
                var lon: f64 = 0;
                var accuracy: f64 = 0;

                const hr_lat = latlng.vtable.GetLatitude(latlng, &lat);
                const hr_lon = latlng.vtable.GetLongitude(latlng, &lon);
                _ = latlng.vtable.GetErrorRadius(latlng, &accuracy);

                if (hr_lat == S_OK and hr_lon == S_OK) {
                    return Location{
                        .latitude = lat,
                        .longitude = lon,
                        .accuracy = accuracy,
                    };
                }
            }
        }

        // Check timeout
        const now: i128 = std.time.nanoTimestamp();
        if (now - start >= timeout_ns) {
            return LocationError.Timeout;
        }

        // Sleep 500ms before retrying
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }
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
