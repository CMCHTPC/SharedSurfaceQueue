// -----------------------------------------------------------------------------
// Implementation of D3D11 Device Wrapper.  This is a simple wrapper around the
// public D3D11 APIs that are necessary for the shared surface queue.  See
// the comments in SharedSurfaceQueue.h to descriptions of these functions.
// -----------------------------------------------------------------------------

unit SurfaceQueueDeviceD3D11;
{$IFDEF FPC}
{$MODE delphi}
{$ENDIF}

interface

uses
    Windows, Classes, SysUtils, SurfaceQueue, DX12.DXGI, DX12.D3D10, DX12.D3D11;

type

    { TSurfaceQueueDeviceD3D11 }

    TSurfaceQueueDeviceD3D11 = class(TInterfacedObject, ISurfaceQueueDevice)
    private
        m_pDevice: ID3D11Device;
    public
        function CreateSharedSurface(Width: UINT; Height: UINT; format: TDXGI_FORMAT; out ppSurface; out phandle: THANDLE): HResult; stdcall;
        function ValidateREFIID(const ID: TGUID): boolean; stdcall;
        function OpenSurface(hSharedHandle: THANDLE; out ppUnknown; Width: UINT; Height: UINT; format: TDXGI_FORMAT): HResult; stdcall;
        function GetSharedHandle(pUnknown: IUnknown; out phandle: THANDLE): HResult; stdcall;
        function CreateCopyResource(format: TDXGI_FORMAT; Width: UINT; Height: UINT; out pRes: IUnknown): HResult; stdcall;

        function CopySurface(pDst: IUnknown; pSrc: IUnknown; Width: UINT; Height: UINT): HResult; stdcall;
        function LockSurface(pSurface: IUnknown; flags: DWORD): HResult; stdcall;
        function UnlockSurface(pSurface: IUnknown): HResult; stdcall;

        constructor Create(pD3D11Device: ID3D11Device);
        destructor Destroy; override;
    end;

implementation

{ TSurfaceQueueDeviceD3D11 }

function TSurfaceQueueDeviceD3D11.CopySurface(pDst, pSrc: IInterface; Width, Height: UINT): HResult;
var
    UnitBox: TD3D11_BOX;
    pContext: ID3D11DeviceContext;
    pSrcRes: ID3D11Resource;
    pDstRes: ID3D11Resource;
begin
    UnitBox.left := 0;
    UnitBox.top := 0;
    UnitBox.front := 0;
    UnitBox.right := Width;
    UnitBox.bottom := Height;
    UnitBox.back := 1;

    pContext := nil;
    pSrcRes := nil;
    pDstRes := nil;

    m_pDevice.GetImmediateContext(pContext);
    // ASSERT(pContext);

    result := pDst.QueryInterface(IID_ID3D11Resource, pDstRes);
    if result = S_OK then

        result := pSrc.QueryInterface(IID_ID3D11Resource, pSrcRes);
    if result = S_OK then

        pContext.CopySubresourceRegion(pDstRes, 0, 0, 0, 0, // (x, y, z)
            pSrcRes, 0, @UnitBox);

    if (pSrcRes <> nil) then
        pSrcRes := nil;
    if (pDstRes <> nil) then
        pDstRes := nil;
    if (pContext <> nil) then
        pContext := nil;

end;

constructor TSurfaceQueueDeviceD3D11.Create(pD3D11Device: ID3D11Device);
begin
    m_pDevice := pD3D11Device;
end;

function TSurfaceQueueDeviceD3D11.CreateCopyResource(format: TDXGI_FORMAT; Width, Height: UINT; out pRes: IInterface): HResult;
var
    Desc: TD3D11_TEXTURE2D_DESC;
begin
    // ASSERT(ppRes);
    // ASSERT(m_pDevice);

    Desc.Width := Width;
    Desc.Height := Height;
    Desc.MipLevels := 1;
    Desc.ArraySize := 1;
    Desc.format := format;
    Desc.SampleDesc.Count := 1;
    Desc.SampleDesc.Quality := 0;
    Desc.Usage := D3D11_USAGE_STAGING;
    Desc.BindFlags := 0;
    Desc.CPUAccessFlags := ord(D3D11_CPU_ACCESS_READ);
    Desc.MiscFlags := 0;

    result := m_pDevice.CreateTexture2D(Desc, nil, ID3D11Texture2D(pRes));
end;

function TSurfaceQueueDeviceD3D11.CreateSharedSurface(Width, Height: UINT; format: TDXGI_FORMAT; out ppSurface; out phandle: THANDLE): HResult;
var
    ppTexture: ID3D11Texture2D;
    Desc: TD3D11_TEXTURE2D_DESC;
begin
    Desc.Width := Width;
    Desc.Height := Height;
    Desc.MipLevels := 1;
    Desc.ArraySize := 1;
    Desc.format := format;
    Desc.SampleDesc.Count := 1;
    Desc.SampleDesc.Quality := 0;
    Desc.Usage := D3D11_USAGE_DEFAULT;
    Desc.BindFlags := ord(D3D11_BIND_RENDER_TARGET) or ord(D3D11_BIND_SHADER_RESOURCE);
    Desc.CPUAccessFlags := 0;
    Desc.MiscFlags := ord(D3D11_RESOURCE_MISC_SHARED);

    result := m_pDevice.CreateTexture2D(Desc, nil, ID3D11Texture2D(ppTexture));

    if (result = S_OK) then
    begin
        result := GetSharedHandle(IUnknown(ppSurface), phandle);
        if (result = S_OK) then
            ppTexture := nil;
    end;

end;

destructor TSurfaceQueueDeviceD3D11.Destroy;
begin
    m_pDevice := nil;
    inherited;
end;

function TSurfaceQueueDeviceD3D11.GetSharedHandle(pUnknown: IInterface; out phandle: THANDLE): HResult;
var
    pSurface: IDXGIResource;
begin
    // ASSERT(pUnknown);
    // ASSERT(pHandle);

    phandle := 0;

    result := pUnknown.QueryInterface(IID_IDXGIResource, pSurface);
    if result <> S_OK then
        Exit;

    result := pSurface.GetSharedHandle(phandle);
    pSurface := nil;
end;

function TSurfaceQueueDeviceD3D11.LockSurface(pSurface: IInterface; flags: DWORD): HResult;
var
    region: TD3D11_MAPPED_SUBRESOURCE;
    pResource: ID3D11Resource;
    pContext: ID3D11DeviceContext;
    d3d11flags: DWORD;
begin
    // ASSERT(pSurface);

    pResource := nil;
    pContext := nil;
    d3d11flags := 0;

    m_pDevice.GetImmediateContext(pContext);
    // ASSERT(pContext);

    if (flags and ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT) = ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT)) then
        d3d11flags := d3d11flags or ord(D3D11_MAP_FLAG_DO_NOT_WAIT);

    result := pSurface.QueryInterface(IID_ID3D11Resource, pResource);
    if result = S_OK then
        result := pContext.Map(pResource, 0, D3D11_MAP_READ, d3d11flags, region);

    if (pResource <> nil) then
        pResource := nil;

    if (pContext <> nil) then
        pContext := nil;

end;

function TSurfaceQueueDeviceD3D11.OpenSurface(hSharedHandle: THANDLE; out ppUnknown; Width, Height: UINT; format: TDXGI_FORMAT): HResult;
begin
    result := m_pDevice.OpenSharedResource(hSharedHandle, IID_ID3D11Texture2D, ppUnknown);
end;

function TSurfaceQueueDeviceD3D11.UnlockSurface(pSurface: IInterface): HResult;
var
    pContext: ID3D11DeviceContext;
    pResource: ID3D11Resource;
begin
    // ASSERT(pSurface);
    pContext := nil;
    pResource := nil;

    m_pDevice.GetImmediateContext(pContext);
    // ASSERT(pContext);

    result := pSurface.QueryInterface(IID_ID3D11Resource, pResource);
    if (result = S_OK) then
        pContext.Unmap(pResource, 0);

    if (pResource <> nil) then
        pResource := nil;
    if (pContext <> nil) then
        pContext := nil;
end;

function TSurfaceQueueDeviceD3D11.ValidateREFIID(const ID: TGUID): boolean;
begin
    result := IsEqualGUID(ID3D11Texture2D, ID) or IsEqualGUID(IDXGISurface, ID);
end;

end.
