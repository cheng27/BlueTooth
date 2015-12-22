//
//  QYBTCentralVC.m
//  01-CoreBluetoothDemo
//
//  Created by qingyun on 15/12/22.
//  Copyright © 2015年 qingyun. All rights reserved.
//

#import "QYBTCentralVC.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "QYTransfer.h"

@interface QYBTCentralVC () <CBCentralManagerDelegate,CBPeripheralDelegate>
@property (weak, nonatomic) IBOutlet UISwitch *scanSwitch;
@property (weak, nonatomic) IBOutlet UITextView *textView;

@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic,strong) CBPeripheral *discoveredPeripheral;
@property (nonatomic,strong) NSMutableData *data;

@end

@implementation QYBTCentralVC

#pragma mark - view life cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. 创建central manager对象
    _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
}

#pragma mark - setter & getter
- (NSMutableData *)data
{
    if (_data == nil) {
        _data = [NSMutableData data];
    }
    return _data;
}

#pragma mark - CBCentralManagerDelegate

// 当CentralManager 的状态改变之后的回调，当centralManager对象创建时也会调用该方法
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state != CBCentralManagerStatePoweredOn) {
        NSLog(@"[INFO]: 蓝牙未开启!");
        return;
    }
}
// 当CentraLManager发现Peripheral设备发出的AD报文时，调用该方法
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI
{
    //如果已经发现过该设备，则直接返回，否则保存该设备并开始连接该设备
    if (self.discoveredPeripheral == peripheral) {
        return;
    }
    NSLog(@"[INFO]:发现Peripheral设备 <%@> - <%@>",peripheral.name,RSSI);
    self.discoveredPeripheral = peripheral;
    peripheral.delegate = self;
    [self.centralManager connectPeripheral:peripheral options:nil];
}

//当centralManager 连接Peripheral设备失败时的回调
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"[ERROR]:连接%@失败!(%@)",peripheral,error);
}

//当centralManager连接Peripheral设备成功时的回调
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    //一旦连接成功，就立刻停止扫描
    [self.centralManager stopScan];
    NSLog(@"[INFO]:正在停止扫描...");
    
    //清空已经存储的数据，为了重新接收数据
    self.data.length = 0;
    
    //发现服务 - 根据UUID去发现我们感兴趣的服务
    [peripheral discoverServices:@[[CBUUID UUIDWithString:TRANSFER_SERVER_UUID]]];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    if (error) {
        NSLog(@"[ERROR]:断开连接失败!(%@)",error);
        [self cleanup];
        return;
    }
    NSLog(@"[INFO]:连接已断开!");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _scanSwitch.on = NO;
    });
    self.discoveredPeripheral = nil;
}

#pragma mark CBPeripheralDelegate

//发现服务(Services)之后的回调
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"[ERROR]:Peripheral设备发现服务(services)失败!(%@)",error);
        [self cleanup];
        return;
    }
    
    //遍历Peripheral设备所有的服务，去发现所需要的Characteristics
    for (CBService *service in peripheral.services) {
        [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]] forService:service];
    }
}
//发现特性(Characteristics)之后的回调
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if (error) {
        NSLog(@"[ERROR]:Peripheral设备发现特性(charateristics)失败!(%@)",error);
        [self cleanup];
        return;
    }
    //遍历该Services的所有Characteristics，然后去订阅这些Characteristics
    for (CBCharacteristic *characteristics in service.characteristics) {
        //订阅该Characteristics
        [peripheral setNotifyValue:YES forCharacteristic:characteristics];
    }
}
//收到数据更新之后的回调
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"[ERROR]:更新数据失败!(%@)",error);
        [self cleanup];
        return;
    }
    //取出数据
    NSData *data = characteristic.value;
    //解析数据
    [self parseData:data withPeripheral:peripheral andCharacteristic:characteristic];
    
}

//订阅状态发生变化时的回调
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"[ERROR]:setNotifyValue:forCharacteristics:失败!(%@)",error);
        [self cleanup];
        return;
    }
    if (characteristic.isNotifying) {
        NSLog(@"[INFO]:已经订阅 %@",characteristic);
    }else
    {
        NSLog(@"[INFO]:取消订阅 %@",characteristic);
    }
}


#pragma mark - misc process
- (void)cleanup
{
    if (self.discoveredPeripheral.state != CBPeripheralStateConnected) {
        return;
    }
    
    //遍历所有服务（Sevrices）的特性（Characteristics），并且取消订阅
    if (self.discoveredPeripheral.services) {
        for (CBService *service in self.discoveredPeripheral.services) {
            if (service.characteristics) {
                for (CBCharacteristic *characteritics in service.characteristics) {
                    if ([characteritics.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]]) {
                        [self.discoveredPeripheral setNotifyValue:NO forCharacteristic:characteritics];
                    }
                }
            }
        }

    }
}
//解析数据
- (void)parseData:(NSData *)data withPeripheral:(CBPeripheral *)peripheral andCharacteristic:(CBCharacteristic *)characteristic
{
    NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"[DEBUG]:已收到 - %@",dataStr);
    
    //接收数据完毕 - EOM (End Of Message)
    if ([dataStr isEqualToString:EOM]) {
        //更新UI
        _textView.text = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
        
        //取消订阅
        [peripheral setNotifyValue:NO forCharacteristic:characteristic];
        
        //断开连接
        [self.centralManager cancelPeripheralConnection:peripheral];
        return;
    }
    //拼接数据
    [self.data appendData:data];
}

#pragma mark - events handling
- (IBAction)toggleScan:(UISwitch *)sender {
    if (sender.on) {
        // scan
        [self.centralManager scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:TRANSFER_SERVER_UUID]] options:0];
        NSLog(@"[INFO]:开始扫描!");
        
    } else {
        // stop scan
        [self.centralManager stopScan];
    }
}

@end
