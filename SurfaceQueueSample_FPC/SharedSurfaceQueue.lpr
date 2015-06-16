program SharedSurfaceQueue;

{$mode delphi}{$H+}

uses {$IFDEF UNIX} {$IFDEF UseCThreads}
    cthreads, {$ENDIF} {$ENDIF}
    Interfaces,
    pl_win_directx, // this includes the LCL widgetset
    SysUtils,
    Direct3D9,
    DX12.DXGI,
    DX12.D3D10_1,
    DX12.D3D10,
    D3DX9,
    DX12.D3DX10,
    DX12.D3DCommon,
    SRWLock,
    SurfaceQueue,
    SurfaceQueueDeviceD3D9,
    SurfaceQueueDeviceD3D10,
    SurfaceQueueDeviceD3D11,
    Windows;

{$R *.res}


const
    TEXTURE_PATH = 'DirectX.bmp';
    EFFECT_PATH = 'TextureMap.fx';
    Width = 640;
    Height = 480;

type
    TSimpleVertex = record
        Pos: TD3DXVECTOR3;
        Tex: TD3DXVECTOR2;
    end;

var
    gHandle: Hwnd;
    g_D3D9: IDirect3D9Ex;
    g_D3D9Device: IDirect3DDevice9Ex;
    g_D3D9Font: ID3DXFONT;

    g_D3D10Device: ID3D10Device1;
    g_D3D10Technique: ID3D10EffectTechnique;
    g_D3D10Matrix: ID3D10EffectMatrixVariable;

    pVertexLayout: ID3D10InputLayout;
    pVertexBuffer: ID3D10Buffer;
    pIndexBuffer: ID3D10Buffer;
    pTextureRV: ID3D10ShaderResourceView;
    pTextureVariable: ID3D10EffectShaderResourceVariable;
    pRS: ID3D10RasterizerState;
    lEffectVar: ID3D10EffectVariable;
    lEffectpDesc: TD3D10_EFFECT_DESC;
    lMatrixDesc: TD3D10_EFFECT_VARIABLE_DESC;

    pEffect: ID3D10Effect;

    g_ABQueue: ISurfaceQueue;
    g_BAQueue: ISurfaceQueue;

    gVERTEX_DATA: array [0 .. 3] of TSimpleVertex;
    gINDEX_DATA: array [0 .. 5] of ulong = (0, 1, 2, 0, 2, 3);

    s_TicksPerSecond: int64;
    s_FPSUpdateInterval: int64;

    CurrentTime, LastTime, LastFPSUpdate: int64;
    NumFrames: UINT;
    FPS: single;
    gSCount: INT32 = 0;



    procedure SafeRelease(Obj: IUnknown);
    begin
        if Obj <> nil then
            Obj := nil;
    end;



    function WndProc(Handle: Hwnd; umessage: UINT; wPara: WPARAM; lPara: LPARAM): LRESULT; stdcall;
    var
        ps: PAINTSTRUCT;
        // hdc:HDC;
    begin
        case (umessage) of
            WM_PAINT:
            begin
                BeginPaint(Handle, ps);
                EndPaint(Handle, ps);
                Result := 0;
            end;

            WM_DESTROY:
            begin
                PostQuitMessage(0);
                Result := 0;
            end;
            else
                Result := DefWindowProc(Handle, umessage, wPara, lPara);
        end;
    end;



    procedure CleanupD3D10;
    begin
        SafeRelease(g_D3D10Device);
    end;



    procedure CleanupD3D9;
    begin
        SafeRelease(g_D3D9Font);
        SafeRelease(g_D3D9Device);
        SafeRelease(g_D3D9);
    end;



    procedure CleanupD3D;
    begin
        SafeRelease(g_ABQueue);
        SafeRelease(g_BAQueue);
        CleanupD3D10();
        CleanupD3D9();
    end;



    function InitWindow: Hwnd;
    var
        wcex: TWndClassEx;
        lHandle: Hwnd;
        FInstance: THandle;
    begin
        // register window class
        FInstance := HInstance;
        wcex.cbSize := SizeOf(wcex);
        wcex.style := CS_HREDRAW or CS_VREDRAW;
        wcex.lpfnWndProc := @WndProc;
        wcex.cbClsExtra := 0;
        wcex.cbWndExtra := 0;
        wcex.HInstance := FInstance;
        wcex.hIcon := 0;
        wcex.hCursor := LoadCursor(0, IDC_ARROW);
        wcex.hbrBackground := HBRUSH(GetStockObject(BLACK_BRUSH));
        wcex.lpszMenuName := nil;
        wcex.lpszClassName := 'D3DSample';
        wcex.hIconSm := 0;
        if RegisterClassEx(wcex) = 0 then
            Exit;
        lHandle := CreateWindowEx(0, 'D3DSample', 'D3D9/D3D10 Interop Sample', WS_OVERLAPPEDWINDOW, 0, 0, Width, Height, 0, 0, FInstance, nil);
        Result := lHandle;
    end;



    function InitD3D9(Handle: Hwnd): HResult;
    var
        d3dpp: D3DPRESENT_PARAMETERS;
    begin
        Direct3DCreate9Ex(D3D_SDK_VERSION, g_D3D9);
        if (g_D3D9 = nil) then
        begin
            Result := E_FAIL;
            Exit;
        end;
        ZeroMemory(@d3dpp, SizeOf(d3dpp));
        d3dpp.Windowed := True;
        d3dpp.SwapEffect := D3DSWAPEFFECT_DISCARD;
        d3dpp.MultiSampleType := D3DMULTISAMPLE_NONE;
        d3dpp.hDeviceWindow := Handle;
        d3dpp.EnableAutoDepthStencil := True;
        d3dpp.AutoDepthStencilFormat := D3DFMT_D16;
        d3dpp.FullScreen_RefreshRateInHz := 0;
        d3dpp.BackBufferCount := 3;
        d3dpp.PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;
        d3dpp.BackBufferFormat := D3DFMT_X8R8G8B8; // set the back buffer format to 32-bit
        d3dpp.BackBufferWidth := Width; // set the width of the buffer
        d3dpp.BackBufferHeight := Height; // set the height of the buffer

        Result := g_D3D9.CreateDeviceEx(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, Handle, D3DCREATE_HARDWARE_VERTEXPROCESSING, @d3dpp, nil, g_D3D9Device);
        if (Result <> S_OK) then
            Exit;
        Result := D3DXCreateFont(g_D3D9Device, -15, 0, 0, 1, False, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, DEFAULT_QUALITY,
            DEFAULT_PITCH or FF_DONTCARE, 'Arial', g_D3D9Font);
    end;



    function CreateGeometry(pDevice: ID3D10Device; out ppVertexBuffer: ID3D10Buffer; out ppIndexBuffer: ID3D10Buffer): HResult;
    var
        bd: TD3D10_BUFFER_DESC;
        InitData: TD3D10_SUBRESOURCE_DATA;
        stride: UINT;
        offset: UINT;
    begin
        Result := S_OK;

        gVERTEX_DATA[0].Pos := TD3DXVECTOR3.Create(0.5, 0.5, 0);
        gVERTEX_DATA[0].Tex := TD3DXVECTOR2.Create(1.0, 0.0);
        gVERTEX_DATA[1].Pos := TD3DXVECTOR3.Create(0.5, -0.5, 0);
        gVERTEX_DATA[1].Tex := TD3DXVECTOR2.Create(1.0, 1.0);
        gVERTEX_DATA[2].Pos := TD3DXVECTOR3.Create(-0.5, -0.5, 0);
        gVERTEX_DATA[2].Tex := TD3DXVECTOR2.Create(0.0, 1.0);
        gVERTEX_DATA[3].Pos := TD3DXVECTOR3.Create(-0.5, 0.5, 0);
        gVERTEX_DATA[3].Tex := TD3DXVECTOR2.Create(0.0, 0.0);

        bd.Usage := D3D10_USAGE_DEFAULT;
        bd.ByteWidth := SizeOf(gVERTEX_DATA);
        bd.BindFlags := Ord(D3D10_BIND_VERTEX_BUFFER);
        bd.CPUAccessFlags := 0;
        bd.MiscFlags := 0;

        InitData.pSysMem := @gVERTEX_DATA[0];
        InitData.SysMemPitch := 0;
        InitData.SysMemSlicePitch := 0;

        Result := pDevice.CreateBuffer(@bd, @InitData, ppVertexBuffer);
        if Result <> S_OK then
            Exit;

        stride := SizeOf(TSimpleVertex);
        offset := 0;
        pDevice.IASetVertexBuffers(0, 1, @ppVertexBuffer, @stride, @offset);

        bd.Usage := D3D10_USAGE_DEFAULT;
        bd.ByteWidth := SizeOf(gINDEX_DATA);
        bd.BindFlags := Ord(D3D10_BIND_INDEX_BUFFER);
        bd.CPUAccessFlags := 0;
        bd.MiscFlags := 0;

        InitData.pSysMem := @gINDEX_DATA[0];
        InitData.SysMemPitch := 0;
        InitData.SysMemSlicePitch := 0;

        Result := pDevice.CreateBuffer(@bd, @InitData, ppIndexBuffer);
        if Result <> S_OK then
            Exit;

        pDevice.IASetIndexBuffer(ppIndexBuffer, { DXGI_FORMAT_R16_UINT } DXGI_FORMAT_R32_UINT, 0);
        pDevice.IASetPrimitiveTopology(D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    end;



    function InitD3D10: HResult;
    var
        hr: HResult;
        DeviceFlags: UINT;
        dwShaderFlags: DWORD;
        vp: TD3D10_VIEWPORT;

        lErrorBlob: ID3D10Blob;

        numElements: UINT;

        layout: array [0 .. 1] of TD3D10_INPUT_ELEMENT_DESC;
        PassDesc: TD3D10_PASS_DESC;
        rasterizerState: TD3D10_RASTERIZER_DESC;

    begin
        DeviceFlags := 0;
        dwShaderFlags := D3D10_SHADER_ENABLE_STRICTNESS;
{$IFDEF DEBUG}
        DeviceFlags := DeviceFlags or Ord(D3D10_CREATE_DEVICE_DEBUG);
        dwShaderFlags := dwShaderFlags or Ord(D3D10_SHADER_DEBUG);
{$ENDIF}
        Result := D3D10CreateDevice1(nil, D3D10_DRIVER_TYPE_HARDWARE, 0, DeviceFlags, D3D10_FEATURE_LEVEL_10_0, D3D10_1_SDK_VERSION, g_D3D10Device);
        if Result <> S_OK then
            Exit;

        vp.Width := Width;
        vp.Height := Height;
        vp.MinDepth := 0.0;
        vp.MaxDepth := 1.0;
        vp.TopLeftX := 0;
        vp.TopLeftY := 0;
        g_D3D10Device.RSSetViewports(1, @vp);
        // Create the effect

        Result := D3DX10CreateShaderResourceViewFromFileW(g_D3D10Device, TEXTURE_PATH, nil, nil, pTextureRV, hr);
        if Result <> S_OK then
            Exit;
        Result := D3DX10CreateEffectFromFileW(EFFECT_PATH, nil, nil, 'fx_4_0', dwShaderFlags, 0, g_D3D10Device, nil, nil, pEffect, lErrorBlob, hr);
        if Result <> S_OK then
            Exit;

        g_D3D10Technique := pEffect.GetTechniqueByName('Render');
        pTextureVariable := pEffect.GetVariableByName('txDiffuse').AsShaderResource();
        layout[0].SemanticName := 'POSITION';
        layout[0].SemanticIndex := 0;
        layout[0].Format := DXGI_FORMAT_R32G32B32_FLOAT;
        layout[0].InputSlot := 0;
        layout[0].AlignedByteOffset := 0;
        layout[0].InputSlotClass := D3D10_INPUT_PER_VERTEX_DATA;
        layout[0].InstanceDataStepRate := 0;

        layout[1].SemanticName := 'TEXCOORD';
        layout[1].SemanticIndex := 0;
        layout[1].Format := DXGI_FORMAT_R32G32_FLOAT;
        layout[1].InputSlot := 0;
        layout[1].AlignedByteOffset := 12;
        layout[1].InputSlotClass := D3D10_INPUT_PER_VERTEX_DATA;
        layout[1].InstanceDataStepRate := 0;

        numElements := SizeOf(layout) div SizeOf(layout[0]);

        if g_D3D10Technique.IsValid then
            g_D3D10Technique.GetPassByIndex(0).GetDesc(PassDesc);
        Result := g_D3D10Device.CreateInputLayout(@layout[0], numElements, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, pVertexLayout);
        if Result <> S_OK then
            Exit;

        g_D3D10Device.IASetInputLayout(pVertexLayout);
        pTextureVariable.SetResource(pTextureRV);
        if pEffect.IsValid then
            lEffectVar := pEffect.GetVariableByName(pAnsiChar('WorldMatrix'));
        if lEffectVar.IsValid then
            g_D3D10Matrix := lEffectVar.AsMatrix;

        pEffect.GetDesc(lEffectpDesc);
        lEffectVar.GetDesc(lMatrixDesc);

        { Create the geometry }
        Result := CreateGeometry(g_D3D10Device, pVertexBuffer, pIndexBuffer);
        if Result <> S_OK then
            Exit;

        ZeroMemory(@rasterizerState, SizeOf(TD3D10_RASTERIZER_DESC));
        rasterizerState.CullMode := D3D10_CULL_NONE;
        rasterizerState.FillMode := D3D10_FILL_SOLID;

        g_D3D10Device.CreateRasterizerState(@rasterizerState, pRS);
        g_D3D10Device.RSSetState(pRS);

        Result := S_OK;

    end;



    function InitD3D(Handle: Hwnd): HResult;
    var
        desc: TSURFACE_QUEUE_DESC;
        CloneDesc: TSURFACE_QUEUE_CLONE_DESC;
    begin
        Result := InitD3D9(Handle);
        if Result <> S_OK then
            Exit;

        Result := InitD3D10;
        if Result <> S_OK then
            Exit;

        // Initialize the surface queues

        ZeroMemory(@desc, SizeOf(TSURFACE_QUEUE_DESC));

        desc.Width := Width;
        desc.Height := Height;
        desc.Format := DXGI_FORMAT_B8G8R8A8_UNORM;
        desc.NumSurfaces := 3;
        desc.MetaDataSize := SizeOf(INT32);
        desc.Flags := Ord(SURFACE_QUEUE_FLAG_SINGLE_THREADED);

        Result := CreateSurfaceQueue(desc, g_D3D9Device, g_ABQueue);
        if Result <> S_OK then
            Exit;

        // Clone the queue
        ZeroMemory(@CloneDesc, SizeOf(TSURFACE_QUEUE_CLONE_DESC));
        CloneDesc.MetaDataSize := 0;
        CloneDesc.Flags := Ord(SURFACE_QUEUE_FLAG_SINGLE_THREADED);
        Result := g_ABQueue.Clone(CloneDesc, g_BAQueue);
    end;



    procedure RenderD3D10(Count: INT32);
    var
        angle: single;
        techDesc: TD3D10_TECHNIQUE_DESC;
        matrix: TD3DXMATRIX;
        p: UINT;
        ps, ps1, pm: PSingle;

    begin
        angle := (Count / 200.0);
        D3DXMatrixIdentity(@matrix);
        D3DXMatrixRotationY(@matrix, angle);
        g_D3D10Matrix.SetMatrix(@matrix._11);
        g_D3D10Technique.GetDesc(techDesc);
        for p := 0 to techDesc.Passes - 1 do
        begin
            g_D3D10Technique.GetPassByIndex(p).Apply(0);
            g_D3D10Device.DrawIndexed(6, 0, 0);
        end;
    end;



    function UpdateFPS: single;
    var
        lCurrentTime: single;
        lLastTime: single;
    begin
        QueryPerformanceCounter(CurrentTime);
        // Update FPS
        Inc(NumFrames);
        if (CurrentTime - LastFPSUpdate >= s_FPSUpdateInterval) then
        begin
            lCurrentTime := CurrentTime / s_TicksPerSecond;
            lLastTime := LastFPSUpdate / s_TicksPerSecond;
            FPS := NumFrames / (lCurrentTime - lLastTime);
            LastFPSUpdate := CurrentTime;
            NumFrames := 0;
        end;
        LastTime := CurrentTime;
        Result := FPS;
    end;



    function RenderD3D9: HResult;
    var
        Rect: TRect;
        lFPS: single;
        fpsBuffer: WideString;
    begin
        Rect.Left := 0;
        Rect.Top := 0;
        Rect.Right := 200;
        Rect.Bottom := 15;

        Result := g_D3D9Device.BeginScene();
        if Result <> S_OK then
            Exit;

        lFPS := UpdateFPS();
        fpsBuffer := SysUtils.Format('FPS: %.2f', [lFPS]);
        g_D3D9Font.DrawTextW(nil, pWideChar(fpsBuffer), -1, @Rect, 0, D3DCOLOR_XRGB(255, 255, 255));

        Rect.Top := 15;
        Rect.Bottom := 30;
        fpsBuffer := SysUtils.Format('Render time: %.2f', [1000.0 / lFPS]);
        g_D3D9Font.DrawTextW(nil, pWideChar(fpsBuffer), -1, @Rect, 0, D3DCOLOR_XRGB(255, 255, 255));

        Result := g_D3D9Device.EndScene();
    end;



    procedure Start;
    var
        ABConsumer: ISurfaceConsumer;
        BAProducer: ISurfaceProducer;
        BAConsumer: ISurfaceConsumer;
        ABProducer: ISurfaceProducer;

        pSurface10: ID3D10Texture2D;

        pTexture9: IDirect3DTexture9;

        pSurface9: IDirect3DSurface9;
        pBackSurface: IDirect3DSurface9;
        pRenderTargetView: ID3D10RenderTargetView;
        hr: HResult;
        msg: TMsg;
        lNumSurfaces: UINT;

        lCount: UINT;
        lSize: UINT;
        lClearColor: TFloatArray4;
        p: Pointer;
        lBufferSize: UINT;
    begin
        ABConsumer := nil;
        BAProducer := nil;
        BAConsumer := nil;
        ABProducer := nil;
        pRenderTargetView := nil;

        lClearColor[0] := 0;
        lClearColor[1] := 0.15;
        lClearColor[2] := 0.4;
        lClearColor[3] := 1;

        lCount := 0;

        hr := g_BAQueue.OpenProducer(g_D3D10Device, BAProducer);
        if hr = S_OK then
        begin
            hr := g_ABQueue.OpenConsumer(g_D3D10Device, ABConsumer);
        end;
        if hr = S_OK then
        begin
            hr := g_ABQueue.OpenProducer(g_D3D9Device, ABProducer);
        end;
        if hr = S_OK then
        begin
            hr := g_BAQueue.OpenConsumer(g_D3D9Device, BAConsumer);
        end;
        if hr = S_OK then
        begin
            while (msg.message <> WM_QUIT) do
            begin
                if (PeekMessage(msg, 0, 0, 0, PM_REMOVE)) then
                begin
                    TranslateMessage(msg);
                    DispatchMessage(msg);
                end
                else
                begin

                    pSurface10 := nil;
                    pSurface9 := nil;

                    // D3D10 portion
                    begin

                        lSize := SizeOf(INT32);
                        // Dequeue from AB queue
                        hr := ABConsumer.Dequeue(IID_ID3D10Texture2D, p, @lCount, lSize, 0);
                        if hr = S_OK then
                        begin
                            // there's a surface ready to use
                            pSurface10 := ID3D10Texture2D(p);
                            g_D3D10Device.CreateRenderTargetView(pSurface10, nil, pRenderTargetView);
                            g_D3D10Device.OMSetRenderTargets(1, @pRenderTargetView, nil);
                            g_D3D10Device.ClearRenderTargetView(pRenderTargetView, lClearColor);
                            // Render D3D10 content
                            RenderD3D10(gSCount);
                            g_D3D10Device.OMSetRenderTargets(0, nil, nil);
                            pRenderTargetView := nil;
                            // Produce the surface
                            BAProducer.Enqueue(pSurface10, nil, 0, Ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT));
                            pSurface10 := nil;
                        end;
                    end;

                    // D3D9 Portion
                    begin
                        // Dequeue from BA queue
                        lBufferSize := 0;
                        hr := BAConsumer.Dequeue(IID_IDirect3DTexture9, pTexture9, nil, lBufferSize, 0);
                        if hr = S_OK then
                        begin
                            // Get the top level surface from the texture
                            pTexture9.GetSurfaceLevel(0, pSurface9);

                            // Set up render target on d3d9
                            g_D3D9Device.GetRenderTarget(0, pBackSurface);
                            g_D3D9Device.SetRenderTarget(0, pSurface9);

                            // Render d3d9 content
                            RenderD3D9();

                            // Present with D3D9
                            g_D3D9Device.SetRenderTarget(0, pBackSurface);
                            g_D3D9Device.StretchRect(pSurface9, nil, pBackSurface, nil, D3DTEXF_NONE);
                            g_D3D9Device.Present(nil, nil, 0, nil);

                            pBackSurface := nil;
                            pSurface9 := nil;

                            // Produce Surface
                            ABProducer.Enqueue(pTexture9, @gSCount, SizeOf(INT32), Ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT));
                            pTexture9 := nil;

                            Inc(gSCount);
                        end;
                    end;
                    // Flush the AB queue
                    BAProducer.Flush(Ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT), lNumSurfaces);
                    // Flush the BA queue
                    ABProducer.Flush(Ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT), lNumSurfaces);
                end;
            end;
        end;
        SafeRelease(BAProducer);
        SafeRelease(ABProducer);
        SafeRelease(BAConsumer);
        SafeRelease(ABConsumer);
    end;

begin
    // Setup the FPS counter
    QueryPerformanceFrequency(s_TicksPerSecond);
    s_FPSUpdateInterval := s_TicksPerSecond shr 1;

    gHandle := InitWindow;
    if gHandle <> 0 then
    begin
        if InitD3D(gHandle) = S_OK then
        begin
            ShowWindow(gHandle, SW_SHOWNORMAL);
            Start();
            CleanupD3D();
        end;
    end;

end.
