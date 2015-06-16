//-----------------------------------------------------------------------------
// Implementation of D3D10 Device Wrapper.  This is a simple wrapper around the
// public D3D10 APIs that are necessary for the shared surface queue.  See
// the comments in SharedSurfaceQueue.h to descriptions of these functions.
//-----------------------------------------------------------------------------

unit SurfaceQueueDeviceD3D10;

{$IFDEF FPC}
{$mode delphi}
{$ENDIF}

interface

uses
    Windows, Classes, SysUtils, SurfaceQueue, DX12.DXGI, DX12.D3D10, DX12.D3D10_1;

type

    { TSurfaceQueueDeviceD3D10 }

    TSurfaceQueueDeviceD3D10 = class(TInterfacedObject, ISurfaceQueueDevice)
    private
        m_pDevice: ID3D10Device;
    public
        function CreateSharedSurface(Width: UINT; Height: UINT; format: TDXGI_FORMAT; out ppSurface;
            out phandle: THANDLE): HResult; stdcall;
        function ValidateREFIID(const ID: TGUID): boolean; stdcall;
        function OpenSurface(hSharedHandle: THANDLE; out ppUnknown; Width: UINT; Height: UINT; format: TDXGI_FORMAT): HResult; stdcall;
        function GetSharedHandle(pUnknown: IUnknown; out pHandle: THANDLE): HResult; stdcall;
        function CreateCopyResource(Format: TDXGI_FORMAT; Width: UINT; Height: UINT; out pRes: IUnknown): HResult; stdcall;

        function CopySurface(pDst: IUnknown; pSrc: IUnknown; Width: UINT; Height: UINT): HResult; stdcall;
        function LockSurface(pSurface: IUnknown; flags: DWORD): HResult; stdcall;
        function UnlockSurface(pSurface: IUnknown): HResult; stdcall;

        constructor Create(pD3D10Device: ID3D10Device);
        destructor Destroy; override;
    end;

implementation

{ TSurfaceQueueDeviceD3D10 }

function TSurfaceQueueDeviceD3D10.CreateSharedSurface(Width: UINT; Height: UINT; format: TDXGI_FORMAT; out ppSurface;
    out phandle: THANDLE): HResult; stdcall;
var
    ppTexture: ID3D10Texture2D;
    Desc: TD3D10_TEXTURE2D_DESC;
begin
    // ASSERT(m_pDevice);
    // ASSERT(ppUnknown);
    // ASSERT(pHandle);

    Desc.Width := Width;
    Desc.Height := Height;
    Desc.MipLevels := 1;
    Desc.ArraySize := 1;
    Desc.Format := format;
    Desc.SampleDesc.Count := 1;
    Desc.SampleDesc.Quality := 0;
    Desc.Usage := D3D10_USAGE_DEFAULT;
    Desc.BindFlags := Ord(D3D10_BIND_RENDER_TARGET) or Ord(D3D10_BIND_SHADER_RESOURCE);
    Desc.CPUAccessFlags := 0;
    Desc.MiscFlags := Ord(D3D10_RESOURCE_MISC_SHARED);

    Result := m_pDevice.CreateTexture2D(@Desc, nil, ID3D10Texture2D(ppSurface));

    if (Result = S_OK) then
    begin
        Result := GetSharedHandle(IUnknown(ppSurface), pHandle);
        if (Result = S_OK) then
            ppTexture := nil;
    end;
end;



function TSurfaceQueueDeviceD3D10.ValidateREFIID(const ID: TGUID): boolean;
    stdcall;
begin
    result:=IsEqualGUID(ID3D10Texture2D,iD) or IsEqualGUID(IDXGISurface,iD);
end;



function TSurfaceQueueDeviceD3D10.OpenSurface(hSharedHandle: THANDLE; out ppUnknown; Width: UINT;
    Height: UINT; format: TDXGI_FORMAT): HResult; stdcall;
begin
    Result := m_pDevice.OpenSharedResource(hSharedHandle, IID_ID3D10Texture2D, ppUnknown);
end;



function TSurfaceQueueDeviceD3D10.GetSharedHandle(pUnknown: IUnknown; out pHandle: THANDLE): HResult; stdcall;
var
    pSurface: IDXGIResource;
begin
    //ASSERT(pUnknown);
    //ASSERT(pHandle);
    pHandle := 0;

    Result := pUnknown.QueryInterface(IID_IDXGIResource, pSurface);
    if Result <> S_OK then
        Exit;
    Result := pSurface.GetSharedHandle(pHandle);
    pSurface := nil;
end;



function TSurfaceQueueDeviceD3D10.CreateCopyResource(Format: TDXGI_FORMAT; Width: UINT; Height: UINT; out pRes: IUnknown): HResult; stdcall;
var
    Desc: TD3D10_TEXTURE2D_DESC;
begin
    // ASSERT(ppRes);
    //  ASSERT(m_pDevice);


    Desc.Width := Width;
    Desc.Height := Height;
    Desc.MipLevels := 1;
    Desc.ArraySize := 1;
    Desc.Format := format;
    Desc.SampleDesc.Count := 1;
    Desc.SampleDesc.Quality := 0;
    Desc.Usage := D3D10_USAGE_STAGING;
    Desc.BindFlags := 0;
    Desc.CPUAccessFlags := Ord(D3D10_CPU_ACCESS_READ);
    Desc.MiscFlags := 0;

    Result := m_pDevice.CreateTexture2D(@Desc, nil, ID3D10Texture2D(pRes));
end;



function TSurfaceQueueDeviceD3D10.CopySurface(pDst: IUnknown; pSrc: IUnknown; Width: UINT; Height: UINT): HResult; stdcall;
var
    UnitBox: TD3D10_BOX;
    pSrcRes: ID3D10Resource;
    pDstRes: ID3D10Resource;
begin
    UnitBox.left := 0;
    UnitBox.top := 0;
    UnitBox.front := 0;
    UnitBox.right := Width;
    UnitBox.bottom := Height;
    UnitBox.back := 1;


    pSrcRes := nil;
    pDstRes := nil;

    Result := pDst.QueryInterface(IID_ID3D10Resource, pDstRes);
    if Result = S_OK then
        Result := pSrc.QueryInterface(IID_ID3D10Resource, pSrcRes);
    if Result = S_OK then
        m_pDevice.CopySubresourceRegion(pDstRes, 0, 0, 0, 0, //(x, y, z)
            pSrcRes, 0, @UnitBox);
    if (pSrcRes <> nil) then
        pSrcRes := nil;
    if (pDstRes <> nil) then
        pDstRes := nil;
end;



function TSurfaceQueueDeviceD3D10.LockSurface(pSurface: IUnknown; flags: DWORD): HResult; stdcall;
var
    pTex2D: ID3D10Texture2D;
    d3d10flags: DWORD;
    region: TD3D10_MAPPED_TEXTURE2D;
begin
    // ASSERT(pSurface);

    Result := S_OK;
    pTex2D := nil;
    d3d10flags := 0;


    if (flags and ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT) = ord(SURFACE_QUEUE_FLAG_DO_NOT_WAIT)) then
    begin
        flags := flags or ord(D3D10_MAP_FLAG_DO_NOT_WAIT);
    end;
    Result := pSurface.QueryInterface(IID_ID3D10Texture2D, pTex2D);
    if Result = S_OK then
        Result := pTex2D.Map(0, D3D10_MAP_READ, d3d10flags, region);

    if (pTex2D <> nil) then
        pTex2D := nil;
end;



function TSurfaceQueueDeviceD3D10.UnlockSurface(pSurface: IUnknown): HResult;
    stdcall;
var
    pTex2D: ID3D10Texture2D;
begin
    // ASSERT(pSurface);

    Result := S_OK;
    pTex2D := nil;
    Result := pSurface.QueryInterface(IID_ID3D10Texture2D, pTex2D);
    if Result <> s_OK then
        exit;

    pTex2D.Unmap(0);
    pTex2D := nil;
end;



constructor TSurfaceQueueDeviceD3D10.Create(pD3D10Device: ID3D10Device);
begin
    m_pDevice := pD3D10Device;
end;



destructor TSurfaceQueueDeviceD3D10.Destroy;
begin
    m_pDevice := nil;
    inherited Destroy;
end;

end.
