using System;
using System.Collections.Generic;
using System.Threading;
namespace RecoveryTests {
 public sealed class Backend : EmergencyConsole.IDeviceBackend {
  readonly object gate=new object();EmergencyConsole.PortSnapshot state=new EmergencyConsole.PortSnapshot();
  public int Restarts;public bool Denied,ScanFails;public string LastTarget;
  public const string Id=@"USB\VID_1A86&PID_7523\TEST_B";
  public const string Other=@"USB\VID_1A86&PID_7523\TEST_OTHER";
  public void Set(int problem,string port,bool other){lock(gate){state=problem<0?new EmergencyConsole.PortSnapshot():new EmergencyConsole.PortSnapshot{Ports=problem==0?new[]{port}:new string[0],Devices=other?new[]{D(Id,port,problem),D(Other,"COM9",0)}:new[]{D(Id,port,problem)}};}}
  public static EmergencyConsole.UsbSerialDevice D(string id,string port,int p){return new EmergencyConsole.UsbSerialDevice{Id=id,Name="USB-SERIAL CH340 ("+port+")",Port=port,Problem=p};}
  public EmergencyConsole.PortSnapshot Scan(){lock(gate){if(ScanFails)throw new Exception("injected enumeration failure");return new EmergencyConsole.PortSnapshot{Ports=(string[])state.Ports.Clone(),Devices=(EmergencyConsole.UsbSerialDevice[])state.Devices.Clone()};}}
  public string Restart(string id){lock(gate){Restarts++;LastTarget=id;if(Denied)throw new UnauthorizedAccessException("需要管理员权限；请点击管理员修复。");Set(0,"COM3",false);return "mock CH340 restarted";}}
 }
 public sealed class Transport : EmergencyConsole.ITransport {
  public ConsoleTests.FakeTransport Inner=new ConsoleTests.FakeTransport();public volatile bool Fault;public bool Denied,Disposed;
  public bool IsOpen{get{return Inner.IsOpen;}}
  public void Open(){if(Denied)throw new UnauthorizedAccessException("injected occupied COM");Inner.Open();}
  public void Close(){Inner.Close();}public void Dispose(){Disposed=true;Inner.Dispose();}
  public void Write(byte[] a,int o,int n){if(Fault)throw new System.IO.IOException("injected USB removal");Inner.Write(a,o,n);}
  public int Read(byte[] a,int o,int n){if(Fault)throw new System.IO.IOException("injected USB removal");return Inner.Read(a,o,n);}
 }
 public static class Pool {
  public static List<Transport> All=new List<Transport>();public static bool DenyNext;
  public static EmergencyConsole.Session Create(){var t=new Transport{Denied=DenyNext};DenyNext=false;All.Add(t);return new EmergencyConsole.Session(t,35,25);}
 }
 public static class Checks {
  static int n;static void A(bool ok,string why){n++;if(!ok)throw new Exception("RECOVERY: "+why);}
  public static int Policy(){
   var s=new EmergencyConsole.PortSnapshot();A(EmergencyConsole.RecoveryPolicy.Target(s,"","")==null,"absent wait");
   s.Devices=new[]{Backend.D(Backend.Id,"COM3",10)};
   var t=EmergencyConsole.RecoveryPolicy.Target(s,"","");A(t.Id==Backend.Id,"unique CH340 code10");
   A(EmergencyConsole.RecoveryPolicy.CanAutoRepair(t,false),"code10 eligible");A(!EmergencyConsole.RecoveryPolicy.CanAutoRepair(t,true),"never restart active owner");
   A(!EmergencyConsole.RecoveryPolicy.CanAutoRepair(Backend.D(Backend.Id,"COM3",0),false),"healthy no restart");
   A(!EmergencyConsole.RecoveryPolicy.CanAutoRepair(Backend.D(Backend.Id,"COM3",28),false),"missing driver not reset loop");
   A(!EmergencyConsole.RecoveryPolicy.CanAutoRepair(Backend.D(@"USB\VID_1234&PID_5678\OTHER","COM3",10),false),"unrelated device excluded");
   s.Devices=new[]{Backend.D(Backend.Id,"COM8",0),Backend.D(Backend.Other,"COM9",0)};
   A(EmergencyConsole.RecoveryPolicy.Target(s,"","")==null,"multiple no guessing");
   A(EmergencyConsole.RecoveryPolicy.Target(s,Backend.Id,"").Port=="COM8","identity follows COM renumber");
   A(EmergencyConsole.RecoveryPolicy.Target(s,"","COM9").Id==Backend.Other,"explicit selection");
   A(EmergencyConsole.RecoveryPolicy.Target(s,"missing","")==null,"missing pinned device not replaced");
   s.Error="enumeration failed";A(EmergencyConsole.RecoveryPolicy.Target(s,Backend.Id,"")==null,"failed enumeration cannot reset stale device");
   A(EmergencyConsole.RecoveryPolicy.RetryDelay(1)==2000,"release delay");A(EmergencyConsole.RecoveryPolicy.RetryDelay(2)==4000,"backoff4");A(EmergencyConsole.RecoveryPolicy.RetryDelay(3)==8000,"backoff8");A(EmergencyConsole.RecoveryPolicy.RetryDelay(20)==15000,"backoff capped");
   return n;
  }
 }
}
