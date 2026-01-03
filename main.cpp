#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

extern "C" void fill_xor_bgra_avx2(uint32_t* dst, int width, int height, uint32_t t);

static const int W = 960;
static const int H = 540;

static uint32_t* gPixels = nullptr;
static BITMAPINFO gBI = {};

LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hWnd, &ps);

        StretchDIBits(
            hdc,
            0, 0, W, H,
            0, 0, W, H,
            gPixels,
            &gBI,
            DIB_RGB_COLORS,
            SRCCOPY
        );

        EndPaint(hWnd, &ps);
        return 0;
    }
    }
    return DefWindowProc(hWnd, msg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE, LPSTR, int) {
    WNDCLASSA wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = "XorAvx2Wnd";
    RegisterClassA(&wc);

    HWND hWnd = CreateWindowA(
        wc.lpszClassName, "AVX2 XOR Pattern Demo",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, W + 16, H + 39,
        nullptr, nullptr, hInst, nullptr
    );

    gPixels = (uint32_t*)VirtualAlloc(nullptr, (size_t)W * (size_t)H * 4,
                                      MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (!gPixels) return 1;

    gBI.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    gBI.bmiHeader.biWidth = W;
    gBI.bmiHeader.biHeight = -H; // top-down
    gBI.bmiHeader.biPlanes = 1;
    gBI.bmiHeader.biBitCount = 32;
    gBI.bmiHeader.biCompression = BI_RGB;

    MSG msg;
    uint32_t t = 0;

    for (;;) {
        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) return 0;
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        fill_xor_bgra_avx2(gPixels, W, H, t);
        t += 1;

        InvalidateRect(hWnd, nullptr, FALSE);
        Sleep(16);
    }
}
