//
//  ViewController.m
//  ios-bluetooth-central
//
//  Created by Simon Taylor on 23/09/2022.
//

#import "ViewController.h"

#import <mach/mach_time.h>
#import <os/log.h>
#import <os/signpost.h>

static uint64_t getMachTimestampUs() {
    // Get conversion factors from ticks to nanoseconds
    struct mach_timebase_info timebase;
    mach_timebase_info(&timebase);
    
    // convert to us
    uint64_t ticks = mach_absolute_time();
    uint64_t machTimeUs = (ticks * timebase.numer) / (timebase.denom * 1000);
    return machTimeUs;
}

@interface ViewController ()

@end

@implementation ViewController
{
    CBCentralManager* centralManager_;
    CBUUID* serviceUuid_;
    CBUUID* countCharacteristicUuid_;
    CBUUID* channelCharacteristicUuid_;
    CBL2CAPChannel* openChannel_;
    
    CBPeripheral* peripheral_;
    
    os_log_t _characteristicUpdateLog;
    os_log_t _characteristicGapLog;
    os_log_t _streamDataLog;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self startClient];
}

- (void)startClient {
    centralManager_ = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];
    serviceUuid_ = [CBUUID UUIDWithString:@"13640001-4EC4-4D67-AEAC-380C85DF4043"];
    countCharacteristicUuid_ = [CBUUID UUIDWithString:@"13640002-4EC4-4D67-AEAC-380C85DF4043"];
    channelCharacteristicUuid_ = [CBUUID UUIDWithString:@"13640003-4EC4-4D67-AEAC-380C85DF4043"];
    
    _characteristicUpdateLog = os_log_create("com.zappar.BLE", "Characteristic Updates");
    _characteristicGapLog = os_log_create("com.zappar.BLE", "Characteristic Update Gaps");
    _streamDataLog = os_log_create("com.zappar.BLE", "Stream Data");
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if(central.state >= CBManagerStatePoweredOn) {
        NSLog(@"Starting scan");
        [centralManager_ scanForPeripheralsWithServices:@[serviceUuid_] options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *, id> *)advertisementData RSSI:(NSNumber *)RSSI {
    NSLog(@"Discovered %@", peripheral.name);
    if([@"iOS Demo" isEqualToString:advertisementData[CBAdvertisementDataLocalNameKey]]) {
        peripheral_ = peripheral;
        [centralManager_ stopScan];
        [centralManager_ connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"Connected");
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(nullable NSError *)error {
    NSLog(@"Discovered services");
    for (CBService *service in peripheral.services) {
       NSLog(@"Discovered service %@", service);
        if([service.UUID.data isEqualToData:serviceUuid_.data]) {
            NSLog(@"Found service");
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(nullable NSError *)error {
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSLog(@"Discovered characteristic %@", characteristic);
        if([characteristic.UUID.data isEqualToData:countCharacteristicUuid_.data]) {
            NSLog(@"Found the notification characteristic");
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }
        if([characteristic.UUID.data isEqualToData:channelCharacteristicUuid_.data]) {
            NSLog(@"Found the L2CAP PSM characteristic, asking for a read");
            [peripheral readValueForCharacteristic:characteristic];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error {
    uint64_t callbackTime = getMachTimestampUs();
    static uint64_t lastCallbackTime = 0;
    
    if([characteristic.UUID.data isEqualToData:countCharacteristicUuid_.data]) {
        // Update the controller state from the BLE data
        const uint16_t* cbData = (const uint16_t*)characteristic.value.bytes;
        os_signpost_event_emit(_characteristicUpdateLog, OS_SIGNPOST_ID_EXCLUSIVE, "New data", "Value: %hi", cbData[0]);
        
        NSLog(@"Received updated count: %hu, gap %llu", cbData[0], callbackTime - lastCallbackTime);
        if(callbackTime - lastCallbackTime > 100000) {
            os_signpost_event_emit(_characteristicGapLog, OS_SIGNPOST_ID_EXCLUSIVE, "Big gap", "Gap: %llu us", callbackTime - lastCallbackTime);
            NSLog(@"BIG GAP!");
        }
        lastCallbackTime = callbackTime;
    }
    if([characteristic.UUID isEqual:channelCharacteristicUuid_]) {
        if(characteristic.value != nil && characteristic.value.length == 2) {
            const uint16_t* cbData = (const uint16_t*)characteristic.value.bytes;
            NSLog(@"Read L2CAP channel PSM: %hu", cbData[0]);
            [peripheral openL2CAPChannel:cbData[0]];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didOpenL2CAPChannel:(nullable CBL2CAPChannel *)channel error:(nullable NSError *)error
{
    NSLog(@"Opened L2CAP Channel");
    if(error != nil) {
        NSLog(@"Error: %@", error);
        return;
    }
    openChannel_ = channel;
    [openChannel_.inputStream setDelegate:self];
    [openChannel_.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                        forMode:NSDefaultRunLoopMode];
    [openChannel_.inputStream open];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    switch(eventCode) {
        case NSStreamEventHasBytesAvailable:
        {
            uint64_t callbackTime = getMachTimestampUs();
            static uint64_t lastCallbackTime = 0;
            
            uint8_t buf[1024];
            NSInteger len = 0;
            len = [(NSInputStream *)stream read:buf maxLength:1024];
            if(len > 0) {
                uint16_t firstValue = *((uint16_t*)buf);
                os_signpost_event_emit(_streamDataLog, OS_SIGNPOST_ID_EXCLUSIVE, "New data", "Value: %hi (Total bytes: %li)", firstValue, len);
                
                NSLog(@"Read %li bytes, gap %llu", len, callbackTime - lastCallbackTime);
                lastCallbackTime = callbackTime;
                for(int i = 0; i < len - 1; i += 2) {
                    NSLog(@"Updated count %hu", *(uint16_t*)(buf + i));
                }
            } else {
                NSLog(@"no buffer!");
            }
            break;
        }
            // continued
    }
}


@end
