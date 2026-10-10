public sealed class QQReplayInputTimelineSample
{
    public int index;
    public double time_s;
    public double? delta_ms;
    public double x, y, z;
    public double? speed;
    public int? lap_index;
    public bool pose_valid;
    public bool break_before;
    public string source_stream;
    public int?[] raw_inputs = new int?[8];
    public bool? forward_related;
}

public sealed class QQReplayInputTimelineData
{
    public QQReplayInputTimelineSample[] samples;
    public int[] raw_fields_available;
}

// Read the complete logical CSV; never use the downsampled route preview for input.
public static class QQReplayInputTimeline
{
    static string[] Split(string line)
    {
        var values = new System.Collections.Generic.List<string>();
        var value = new System.Text.StringBuilder(); bool quoted = false;
        for (int i=0; i<line.Length; i++) {
            char c=line[i];
            if (c=='"') {
                if (quoted && i+1<line.Length && line[i+1]=='"') { value.Append('"'); i++; }
                else quoted=!quoted;
            } else if (c==',' && !quoted) { values.Add(value.ToString()); value.Length=0; }
            else value.Append(c);
        }
        if (quoted) throw new System.IO.InvalidDataException("Unclosed CSV quote in input timeline.");
        values.Add(value.ToString()); return values.ToArray();
    }
    static string Field(string[] row, System.Collections.Generic.Dictionary<string,int> columns, string name)
    {
        int i; return columns.TryGetValue(name,out i) && i<row.Length ? row[i] : "";
    }
    static double? Number(string value)
    {
        double n; return System.Double.TryParse(value,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out n)
            && !System.Double.IsNaN(n) && !System.Double.IsInfinity(n) ? n : (double?)null;
    }
    static int? Integer(string value)
    {
        int n; return System.Int32.TryParse(value,System.Globalization.NumberStyles.Integer,System.Globalization.CultureInfo.InvariantCulture,out n) ? n : (int?)null;
    }
    public static QQReplayInputTimelineData LoadCsv(string path)
    {
        using (var reader = new System.IO.StreamReader(path,System.Text.Encoding.UTF8,true)) {
            string first=reader.ReadLine();
            if (first==null) throw new System.IO.InvalidDataException("Empty input timeline CSV.");
            var columns=new System.Collections.Generic.Dictionary<string,int>(System.StringComparer.OrdinalIgnoreCase);
            string[] header=Split(first); for(int i=0;i<header.Length;i++) columns.Add(header[i],i);
            foreach(string name in new string[]{"time_s","x","y","z","speed"})
                if(!columns.ContainsKey(name)) throw new System.IO.InvalidDataException("Input timeline CSV is missing "+name);
            var available=new System.Collections.Generic.List<int>();
            for(int k=0;k<8;k++) if(columns.ContainsKey("input_bool_candidate_"+(60+k))) available.Add(60+k);
            var rows=new System.Collections.Generic.List<QQReplayInputTimelineSample>(); string line;
            while((line=reader.ReadLine())!=null) {
                if(line.Length==0) continue;
                string[] raw=Split(line);
                double? t=Number(Field(raw,columns,"time_s")), x=Number(Field(raw,columns,"x")), y=Number(Field(raw,columns,"y")), z=Number(Field(raw,columns,"z"));
                if(!t.HasValue || !x.HasValue || !y.HasValue || !z.HasValue)
                    throw new System.IO.InvalidDataException("Invalid time/position at input timeline row "+rows.Count);
                var row=new QQReplayInputTimelineSample(); row.index=rows.Count; row.time_s=t.Value; row.x=x.Value; row.y=y.Value; row.z=z.Value;
                row.delta_ms=rows.Count==0?(double?)null:(row.time_s-rows[rows.Count-1].time_s)*1000.0;
                row.speed=Number(Field(raw,columns,"speed")); row.lap_index=Integer(Field(raw,columns,"lap_index"));
                string valid=Field(raw,columns,"pose_valid"); row.pose_valid=valid=="" || valid.Equals("true",System.StringComparison.OrdinalIgnoreCase) || valid=="1";
                string broken=Field(raw,columns,"pose_break_before"); row.break_before=broken.Equals("true",System.StringComparison.OrdinalIgnoreCase) || broken=="1";
                row.source_stream=Field(raw,columns,"source_stream");
                for(int k=0;k<8;k++) row.raw_inputs[k]=Integer(Field(raw,columns,"input_bool_candidate_"+(60+k)));
                row.forward_related=QQReplayInputCandidates.Forward(row.raw_inputs[2],row.raw_inputs[7]);
                rows.Add(row);
            }
            return new QQReplayInputTimelineData { samples=rows.ToArray(), raw_fields_available=available.ToArray() };
        }
    }
}
