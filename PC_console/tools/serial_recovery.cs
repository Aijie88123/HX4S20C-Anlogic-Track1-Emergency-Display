using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO.Ports;
using System.Management;
using System.Threading;
namespace EmergencyConsole {
 public sealed class UsbSerialDevice {
  public string Id,Name,Port; public int Problem;
  public bool IsCH340 { get { return Id!=null && Id.StartsWith(@"USB\VID_1A86&PID_7523\",StringComparison.OrdinalIgnoreCase); } }
 }
 public sealed class PortSnapshot {
  public string[] Ports=new string[0]; public UsbSerialDevice[] Devices=new UsbSerialDevice[0];
  public string Error="",RepairMessage=""; public long Revision; public bool Repairing,NeedsElevation;
 }
 public interface IDeviceBackend {
  PortSnapshot Scan(); string Restart(string instanceId);
 }
 public sealed class WindowsDeviceBackend : IDeviceBackend {
  public PortSnapshot Scan() {
   var s=new PortSnapshot();s.Ports=SerialPort.GetPortNames();Array.Sort(s.Ports,StringComparer.OrdinalIgnoreCase);
   var ds=new List<UsbSerialDevice>();
   using(var q=new ManagementObjectSearcher(@"SELECT Name,PNPDeviceID,ConfigManagerErrorCode,Present FROM Win32_PnPEntity WHERE PNPDeviceID LIKE 'USB\\VID_1A86&PID_7523\\%'") ) {
    q.Options.Timeout=TimeSpan.FromSeconds(4);
    using(var rows=q.Get())foreach(ManagementObject row in rows)using(row){
     if(row["Present"]==null || !Convert.ToBoolean(row["Present"]))continue;
     var d=new UsbSerialDevice{Id=Convert.ToString(row["PNPDeviceID"]),Name=Convert.ToString(row["Name"]),Problem=Convert.ToInt32(row["ConfigManagerErrorCode"])};
     var m=System.Text.RegularExpressions.Regex.Match(d.Name??"",@"\((COM[0-9]+)\)",System.Text.RegularExpressions.RegexOptions.IgnoreCase);
     d.Port=m.Success?m.Groups[1].Value.ToUpperInvariant():"";if(d.IsCH340)ds.Add(d);
    }
   }
   s.Devices=ds.ToArray();return s;
  }
  public string Restart(string id) {
   // Only an exact, present CH340 instance may be restarted. Never /deviceid or /force.
   var check=Scan();UsbSerialDevice target=null;foreach(var d in check.Devices)if(d.IsCH340 && String.Equals(d.Id,id,StringComparison.OrdinalIgnoreCase))target=d;
   if(target==null)throw new InvalidOperationException("目标CH340已经拔出，未执行修复。");
   if(!IsAdministrator())throw new UnauthorizedAccessException("需要管理员权限修复CH340；请点击管理员修复。");
   if(target.Problem==0 && !String.IsNullOrEmpty(target.Port)) {
    // A manual repair must not evict another healthy serial owner.
    using(var probe=new SerialPort(target.Port,115200,Parity.None,8,StopBits.One)) {
     probe.DtrEnable=false;probe.RtsEnable=false;probe.Handshake=Handshake.None;
     try{probe.Open();probe.Close();}
     catch(UnauthorizedAccessException){throw new InvalidOperationException("串口被其他程序占用或访问被拒绝，请先关闭占用程序；未重启CH340。");}
     catch(System.IO.IOException ex){if((ex.HResult&65535)!=31)throw;}
    }
   }
   string exe=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","pnputil.exe");
   if(id.IndexOf('"')>=0 || id.IndexOf('\r')>=0 || id.IndexOf('\n')>=0)throw new ArgumentException("非法设备实例ID");
   var p=new Process{StartInfo=new ProcessStartInfo(exe,"/restart-device \""+id+"\""){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true}};
   string stdout="",stderr="";p.OutputDataReceived+=(o,e)=>{if(e.Data!=null)stdout+=e.Data+Environment.NewLine;};p.ErrorDataReceived+=(o,e)=>{if(e.Data!=null)stderr+=e.Data+Environment.NewLine;};
   using(p){p.Start();p.BeginOutputReadLine();p.BeginErrorReadLine();if(!p.WaitForExit(12000)){try{p.Kill();}catch{}throw new TimeoutException("CH340修复等待超时；请检查USB连接。");}p.WaitForExit();
    string result=(stdout+stderr).Trim();if(p.ExitCode!=0)throw new InvalidOperationException("CH340修复未完成（"+p.ExitCode+"）："+result);return "已执行CH340定向重启，等待系统重新枚举。";}
  }
  public static bool IsAdministrator(){using(var i=System.Security.Principal.WindowsIdentity.GetCurrent())return new System.Security.Principal.WindowsPrincipal(i).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);}
 }
 public static class RecoveryPolicy {
  public static UsbSerialDevice Target(PortSnapshot s,string preferredId,string selectedPort) {
   if(s==null || s.Error.Length>0)return null;
   if(!String.IsNullOrEmpty(selectedPort)) {foreach(var d in s.Devices)if(String.Equals(d.Port,selectedPort,StringComparison.OrdinalIgnoreCase))return d;return null;}
   if(!String.IsNullOrEmpty(preferredId)){foreach(var d in s.Devices)if(String.Equals(d.Id,preferredId,StringComparison.OrdinalIgnoreCase))return d;return null;}
   return s.Devices.Length==1?s.Devices[0]:null;
  }
  public static bool CanAutoRepair(UsbSerialDevice d,bool ownerRunning){return !ownerRunning && d!=null && d.IsCH340 && d.Problem==10;}
  public static int RetryDelay(int failures){return failures<2?2000:failures==2?4000:failures==3?8000:15000;}
 }
 public sealed class PortMonitor : IDisposable {
  readonly IDeviceBackend backend; readonly object gate=new object(); readonly AutoResetEvent wake=new AutoResetEvent(false);
  readonly Dictionary<string,int> attempts=new Dictionary<string,int>(StringComparer.OrdinalIgnoreCase);
  readonly Dictionary<string,long> lastTry=new Dictionary<string,long>(StringComparer.OrdinalIgnoreCase);
  readonly Stopwatch clock=Stopwatch.StartNew();Thread worker;volatile bool stop;string request;bool manual;
  PortSnapshot snapshot=new PortSnapshot();string repairMessage="等待检测USB串口。";bool repairing,needsElevation;
  public PortMonitor():this(new WindowsDeviceBackend()){}
  public PortMonitor(IDeviceBackend deviceBackend){backend=deviceBackend;}
  public void Start(){if(worker!=null)return;worker=new Thread(Run){IsBackground=true,Name="CH340 enumeration and recovery"};worker.Start();}
  public void Refresh(){wake.Set();}
  public void CompleteExternalRepair(string message){lock(gate){needsElevation=false;repairMessage=message;}Refresh();}
  public PortSnapshot ReadView(){lock(gate){return new PortSnapshot{Ports=(string[])snapshot.Ports.Clone(),Devices=(UsbSerialDevice[])snapshot.Devices.Clone(),Revision=snapshot.Revision,Error=snapshot.Error,RepairMessage=repairMessage,Repairing=repairing,NeedsElevation=needsElevation};}}
  public bool RequestRepair(string id,bool explicitlyRequested,bool ownerRunning){
   lock(gate){
    if(ownerRunning||repairing||request!=null||String.IsNullOrEmpty(id))return false;
    UsbSerialDevice d=null;foreach(var item in snapshot.Devices)if(String.Equals(item.Id,id,StringComparison.OrdinalIgnoreCase))d=item;
    if(d==null||!d.IsCH340||snapshot.Error.Length>0||(!explicitlyRequested && d.Problem!=10))return false;
    int n;long at;if(!explicitlyRequested && (attempts.TryGetValue(id,out n)&&n>=2 || lastTry.TryGetValue(id,out at)&&clock.ElapsedMilliseconds-at<30000))return false;
    request=id;manual=explicitlyRequested;repairing=true;needsElevation=false;repairMessage="正在修复选定CH340；等待重新枚举。";wake.Set();return true;
   }
  }
  void Run(){while(!stop){
   string id;bool explicitRequest;lock(gate){id=request;explicitRequest=manual;request=null;}
   if(id!=null){
    try{
     var fresh=backend.Scan();UsbSerialDevice target=null;foreach(var d in fresh.Devices)if(String.Equals(d.Id,id,StringComparison.OrdinalIgnoreCase))target=d;
     if(target==null || !target.IsCH340 || (!explicitRequest && target.Problem!=10))throw new InvalidOperationException("设备状态已变化，已取消本次自动修复。");
     lock(gate){int n;attempts.TryGetValue(id,out n);attempts[id]=n+1;lastTry[id]=clock.ElapsedMilliseconds;}
     string message=backend.Restart(id);lock(gate){repairMessage=message;needsElevation=false;}
    }catch(UnauthorizedAccessException ex){lock(gate){repairMessage=ex.Message;needsElevation=true;}}
    catch(Exception ex){lock(gate){repairMessage=ex.Message;}}
    finally{lock(gate){repairing=false;}}
   }
   try{var s=backend.Scan();lock(gate){s.Revision=snapshot.Revision+1;snapshot=s;}}
   catch(Exception ex){lock(gate){snapshot=new PortSnapshot{Ports=snapshot.Ports,Devices=snapshot.Devices,Revision=snapshot.Revision+1,Error="串口枚举失败："+ex.Message};}}
   wake.WaitOne(id==null?2000:1000);
  }}
  public void Dispose(){stop=true;wake.Set();if(worker!=null && worker.Join(100))wake.Dispose();}
 }
}
