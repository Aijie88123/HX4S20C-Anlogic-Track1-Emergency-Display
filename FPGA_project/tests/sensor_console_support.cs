namespace SensorConsoleTests {
 public sealed class Transport : EmergencyConsole.ITransport {
  public readonly ConsoleTests.FakeTransport Inner=new ConsoleTests.FakeTransport();
  readonly object gate=new object();readonly System.Collections.Generic.Queue<byte> replies=new System.Collections.Generic.Queue<byte>();readonly System.Collections.Generic.List<string> trace=new System.Collections.Generic.List<string>();
  int owner;public bool ThreadSafe=true;public int ClearRequests;
  public bool IsOpen {get{return Inner.IsOpen;}}public void Open(){Inner.Open();}public void Close(){Inner.Close();}public void Dispose(){Inner.Dispose();}
  public void Set(string text){Inner.Set(text);}public string[] Trace(){lock(gate){return trace.ToArray();}}
  void Reply(string s){foreach(byte b in System.Text.Encoding.ASCII.GetBytes(s+"\r\n"))replies.Enqueue(b);}
  public void Write(byte[] a,int offset,int count){lock(gate){int tid=System.Threading.Thread.CurrentThread.ManagedThreadId;if(owner==0)owner=tid;if(tid!=owner){ThreadSafe=false;throw new System.Exception("sensor session has multiple UART owners");}
   bool binary=count==33&&a[offset]==27;string command=binary?"B"+a[offset+5]:System.Text.Encoding.ASCII.GetString(a,offset,count).TrimEnd('\r','\n');trace.Add(command);
   if(command=="TEMP CLEAR"){ClearRequests++;var s=EmergencyConsole.BoardStatus.Parse(Inner.StatusLine);if(s.TempAlarm==1&&s.TempClearAllowed!=1)Reply("ERR SENSOR_COOL");else{Inner.Set(Inner.StatusLine.Replace("TA=1","TA=0").Replace("TC=1","TC=0"));Reply("OK TEMP REQUEST");}return;}
   if(!binary&&command.StartsWith("DEMO ")&&EmergencyConsole.BoardStatus.Parse(Inner.StatusLine).TempAlarm==1){Reply("ERR SENSOR_LOCK");return;}
   Inner.Write(a,offset,count);
  }}
  public int Read(byte[] a,int offset,int count){lock(gate){if(replies.Count>0){int n=System.Math.Min(count,replies.Count);for(int k=0;k<n;k++)a[offset+k]=replies.Dequeue();return n;}}return Inner.Read(a,offset,count);}
 }
 public static class Checks {
  public static int Assertions;
  static void Assert(bool ok,string text){Assertions++;if(!ok)throw new System.Exception("SENSOR ASSERT: "+text);}
  public static string Status(bool fire,int raw,int valid,int warn,int alarm,int clear,int fault,uint ms){
   string s=fire?ConsoleTests.Checks.Fire():ConsoleTests.Checks.Normal();s=System.Text.RegularExpressions.Regex.Replace(s,@"MS=0x[0-9A-F]{8}","MS=0x"+ms.ToString("X8"));
   if(fire)s=s.Replace("SRC=1","SRC=2");return s.Replace("SENSOR=NONE","SENSOR=DS18B20 TRAW=0x"+unchecked((ushort)raw).ToString("X4")+" TV="+valid+" TW="+warn+" TA="+alarm+" TC="+clear+" TF="+fault);
  }
  public static int ParseFixtures(string path){Assertions=0;int rows=0;bool negative=false,invalid=false,source=false;
   foreach(string line in System.IO.File.ReadAllLines(path)){if(!line.StartsWith("MS=")||!line.Contains(" SENSOR="))continue;var s=EmergencyConsole.BoardStatus.Parse(line);Assert(s.SensorInstalled,"actual RTL sensor identity");rows++;
    string display=EmergencyConsole.Policy.TemperatureText(s);if(s.TempRaw==-162&&s.TempValid==1){Assert(display.Contains("-10.1250"),"signed fractional temperature");negative=true;}
    if(s.TempValid==0){Assert(display.Contains("未知"),"fault must not display stale number as current");invalid=true;}
    if(s.Src==2){Assert(s.TempAlarm==1,"sensor fire origin fixture");source=true;}
   }
   Assert(rows>=10&&negative&&invalid&&source,"actual wire fixture coverage");
   string hot=Status(true,880,1,1,1,0,0,32),cool=Status(true,800,1,1,1,1,0,33),badSensor=Status(true,880,0,1,1,0,3,34);
   Assert(EmergencyConsole.Policy.Caption(EmergencyConsole.BoardStatus.Parse(hot)).Contains("高温触发"),"sensor caption source");
   Assert(EmergencyConsole.Policy.TemperatureText(EmergencyConsole.BoardStatus.Parse(badSensor)).Contains("保持应急"),"fault retains displayed alarm");
   Assert(EmergencyConsole.BoardStatus.Parse(cool).TempClearAllowed==1,"qualified clear decode");
   foreach(string bad in new string[]{hot.Replace("TV=1","TV=2"),hot.Replace("TF=0","TF=3"),hot.Replace("TRAW=0x0370","TRAW=0x10000"),hot.Replace("TRAW=0x0370","TRAW=0xFC00"),hot.Replace("TW=1","TW=0"),cool.Replace("TA=1","TA=0"),hot.Replace("SENSOR=DS18B20","SENSOR=UNKNOWN"),hot.Replace(" TF=0","")}){bool failed=false;try{EmergencyConsole.BoardStatus.Parse(bad);}catch(System.FormatException){failed=true;}Assert(failed,"reject malformed/contradictory sensor state");}
   Assert(!EmergencyConsole.BoardStatus.Parse(ConsoleTests.Checks.Normal()).SensorInstalled,"legacyNONE compatibility");return Assertions;
  }
 }
}
